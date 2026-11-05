#include <libtorrent/session.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/extensions.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/write_resume_data.hpp>
#include <libtorrent/alert_types.hpp>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <sstream>
#include <iomanip>
#include <memory>
#include <vector>
#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <set>

namespace lt = libtorrent;
struct GuardPeer : lt::peer_plugin {
    std::shared_ptr<std::atomic<bool>> blocked;
    explicit GuardPeer(std::shared_ptr<std::atomic<bool>> b) : blocked(std::move(b)) {}
    bool on_request(lt::peer_request const&) override { return blocked->load(); }
};
struct GuardTorrent : lt::torrent_plugin {
    std::shared_ptr<std::atomic<bool>> blocked;
    explicit GuardTorrent(std::shared_ptr<std::atomic<bool>> b) : blocked(std::move(b)) {}
    std::shared_ptr<lt::peer_plugin> new_connection(lt::peer_connection_handle const&) override {
        return std::make_shared<GuardPeer>(blocked);
    }
};
struct Engine {
    lt::session session;
    std::vector<lt::torrent_handle> handles;
    std::vector<std::shared_ptr<std::atomic<bool>>> sharingBlocks;
    std::vector<int> priorities;
    std::vector<std::string> resumePaths;
#ifdef STROM_TESTING
    std::vector<bool> restored;
#endif
    std::set<int> pending;
    std::mutex mutex;
    Engine() {
        lt::settings_pack queueSettings;
        queueSettings.set_int(lt::settings_pack::active_downloads, 3);
        queueSettings.set_int(lt::settings_pack::active_limit, 10);
        queueSettings.set_int(lt::settings_pack::auto_manage_interval, 3);
        queueSettings.set_bool(lt::settings_pack::dont_count_slow_torrents, false);
        session.apply_settings(queueSettings);
#ifdef STROM_TESTING
        lt::settings_pack settings;
        settings.set_bool(lt::settings_pack::enable_dht, false);
        settings.set_bool(lt::settings_pack::enable_lsd, false);
        settings.set_bool(lt::settings_pack::enable_upnp, false);
        settings.set_bool(lt::settings_pack::enable_natpmp, false);
        session.apply_settings(settings);
#endif
    }
    void reorder() {
        std::vector<int> ids;
        for (int i=0; i<int(handles.size()); ++i) if (handles[i].is_valid()) ids.push_back(i);
        std::stable_sort(ids.begin(), ids.end(), [this](int a, int b) { return priorities[a] > priorities[b]; });
        int position = 0;
        for (int id : ids) if (!handles[id].status().is_finished) handles[id].queue_position_set(lt::queue_position_t(position++));
    }
    void collect() {
        std::vector<lt::alert*> alerts; session.pop_alerts(&alerts);
        for (auto* alert : alerts) {
            auto* saved = lt::alert_cast<lt::save_resume_data_alert>(alert);
            auto* failed = lt::alert_cast<lt::save_resume_data_failed_alert>(alert);
            if (!saved && !failed) continue;
            auto h = saved ? saved->handle : failed->handle;
            for (int i=0; i<int(handles.size()); ++i) {
                if (handles[i] != h) continue;
                pending.erase(i);
                if (!saved || resumePaths[i].empty()) break;
                try {
                    auto bytes = lt::write_resume_data_buf(saved->params);
                    std::string temporary = resumePaths[i] + ".tmp";
                    { std::ofstream stream(temporary, std::ios::binary | std::ios::trunc); stream.write(bytes.data(), std::streamsize(bytes.size())); stream.flush(); if (!stream) break; }
                    std::filesystem::rename(temporary, resumePaths[i]);
                } catch (...) { /* Retain previous checkpoint and fall back to recheck. */ }
                break;
            }
        }
    }
    void checkpoint() {
        collect();
        for (int i=0; i<int(handles.size()); ++i) {
            if (!handles[i].is_valid() || resumePaths[i].empty() || pending.count(i)) continue;
            pending.insert(i);
            handles[i].save_resume_data(lt::torrent_handle::save_info_dict);
        }
    }
};
static thread_local std::string last_error;
static std::string json_quote(std::string const& input) {
    std::ostringstream out; out << '"';
    for (unsigned char c : input) {
        switch(c) {
        case '"': out << "\\\""; break;
        case '\\': out << "\\\\"; break;
        case '\n': out << "\\n"; break;
        case '\r': out << "\\r"; break;
        case '\t': out << "\\t"; break;
        default: if (c < 32) out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << int(c) << std::dec; else out << char(c);
        }
    }
    out << '"'; return out.str();
}
extern "C" {
void* strom_create() { try { return new Engine; } catch (std::exception const& e) { last_error=e.what(); return nullptr; } }
void strom_destroy(void* p) { delete static_cast<Engine*>(p); }
const char* strom_last_error() { return last_error.c_str(); }
void strom_free(char* p) { std::free(p); }
void strom_set_torrent_sharing(void* p, int id, int enabled) {
    if (!p) return; auto* e=static_cast<Engine*>(p); std::lock_guard<std::mutex> lock(e->mutex);
    if (id<0 || id>=int(e->handles.size()) || !e->handles[id].is_valid()) return;
    e->sharingBlocks[id]->store(!enabled);
    if (!enabled) e->handles[id].clear_peers();
}
int strom_add(void* p, const char* source, const char* directory, int start_paused, const char* resume_path, int sharing, int allow_missing_source) {
    if (!p || !source || !directory) return -1;
    try {
        auto* e=static_cast<Engine*>(p); lt::add_torrent_params params;
        const bool magnet = std::strncmp(source,"magnet:",7)==0;
        const bool sourceExists = !magnet && std::filesystem::is_regular_file(source);
        if (magnet) params=lt::parse_magnet_uri(source);
        else if (sourceExists) params.ti=std::make_shared<lt::torrent_info>(std::string(source));
        else if (!allow_missing_source) throw std::runtime_error("torrent source is missing");
        const auto expected = params.ti ? params.ti->info_hashes() : params.info_hashes;
#ifdef STROM_TESTING
        bool usedCheckpoint = false;
#endif
        if (resume_path && *resume_path) {
            std::ifstream stream(resume_path, std::ios::binary);
            std::vector<char> buffer((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
            if (!buffer.empty()) {
                lt::error_code error;
                auto saved = lt::read_resume_data(buffer, error);
                if (!error && (!sourceExists || saved.info_hashes == expected)) {
                    params = std::move(saved);
#ifdef STROM_TESTING
                    usedCheckpoint = true;
#endif
                }
            }
        }
        if (!magnet && !sourceExists && !params.ti && !params.info_hashes.has_v1() && !params.info_hashes.has_v2()) throw std::runtime_error("valid resume data is required");
        params.save_path=directory;
        auto guard = std::make_shared<std::atomic<bool>>(sharing == 0);
        params.extensions.push_back([guard](lt::torrent_handle const&, lt::client_data_t) {
            return std::make_shared<GuardTorrent>(guard);
        });
        if (start_paused) { params.flags &= ~lt::torrent_flags::auto_managed; params.flags |= lt::torrent_flags::paused; }
        else { params.flags |= lt::torrent_flags::auto_managed; params.flags &= ~lt::torrent_flags::paused; }
        params.flags |= lt::torrent_flags::duplicate_is_error;
        std::lock_guard<std::mutex> lock(e->mutex);
        auto h=e->session.add_torrent(params);
        e->handles.push_back(h);
        e->sharingBlocks.push_back(guard);
        e->priorities.push_back(3);
        e->resumePaths.emplace_back(resume_path ? resume_path : "");
#ifdef STROM_TESTING
        e->restored.push_back(usedCheckpoint);
#endif
        e->reorder();
        return int(e->handles.size()-1);
    } catch (std::exception const& err) { last_error=err.what(); return -1; }
}
int strom_resume_can_replace_source(const char* resume_path, const char* source) {
    if (!resume_path || !source || !std::filesystem::is_regular_file(source)) return 0;
    try {
        std::ifstream stream(resume_path, std::ios::binary);
        std::vector<char> buffer((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
        if (buffer.empty()) return 0;
        lt::error_code error;
        auto saved = lt::read_resume_data(buffer, error);
        if (error) return 0;
        lt::torrent_info info{std::string(source)};
        return saved.info_hashes == info.info_hashes() ? 1 : 0;
    } catch (...) { return 0; }
}
void strom_checkpoint(void* p, int wait) {
    if (!p) return; auto* e=static_cast<Engine*>(p); std::lock_guard<std::mutex> lock(e->mutex);
    e->checkpoint();
    if (wait) {
        auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
        while (!e->pending.empty() && std::chrono::steady_clock::now() < deadline) {
            e->session.wait_for_alert(std::chrono::milliseconds(100)); e->collect();
        }
    }
}
void strom_remove(void* p, int id) {
    if (!p) return;
    auto* e=static_cast<Engine*>(p); std::lock_guard<std::mutex> lock(e->mutex);
    if(id<0 || id>=int(e->handles.size()) || !e->handles[id].is_valid()) return;
    e->pending.erase(id); e->session.remove_torrent(e->handles[id]);
    e->handles[id] = lt::torrent_handle{};
}
void strom_pause(void* p, int id, int paused) {
    if (!p) return; auto* e=static_cast<Engine*>(p); std::lock_guard<std::mutex> lock(e->mutex);
    if(id<0 || id>=int(e->handles.size()) || !e->handles[id].is_valid()) return;
    if(paused) { e->handles[id].unset_flags(lt::torrent_flags::auto_managed); e->handles[id].pause(); }
    else { e->handles[id].set_flags(lt::torrent_flags::auto_managed); e->handles[id].resume(); e->reorder(); }
}
void strom_priority(void* p, int id, int priority) {
    if (!p) return; auto* e=static_cast<Engine*>(p); std::lock_guard<std::mutex> lock(e->mutex);
    if (id<0 || id>=int(e->handles.size()) || !e->handles[id].is_valid()) return;
    e->priorities[id] = std::clamp(priority, 1, 5); e->reorder();
}
// ---- Watching while downloading ----
// The player reads the file through a small local server inside STRÖM. These calls tell the engine which part of a
// file is needed next and report how many bytes are already on disk in one piece (so the server never hands out holes).
static char* copy_string(std::string const& text) {
    char* copy = static_cast<char*>(std::malloc(text.size() + 1));
    if (copy) std::memcpy(copy, text.c_str(), text.size() + 1);
    return copy;
}
// JSON list of the torrent's files: [{"index":0,"path":"dir/file.mkv","size":123,"offset":0}]. "[]" until metadata is known.
char* strom_files(void* p, int id) {
    if (!p) return nullptr;
    try {
        auto* e=static_cast<Engine*>(p); std::lock_guard<std::mutex> lock(e->mutex);
        if (id<0 || id>=int(e->handles.size()) || !e->handles[id].is_valid()) return nullptr;
        auto ti = e->handles[id].torrent_file();
        std::ostringstream out; out << '[';
        if (ti) {
            auto const& fs = ti->files();
            for (int i=0; i<fs.num_files(); ++i) {
                auto idx = lt::file_index_t(i); if (i) out << ',';
                out << "{\"index\":" << i << ",\"path\":" << json_quote(fs.file_path(idx)) << ",\"size\":" << fs.file_size(idx) << ",\"offset\":" << fs.file_offset(idx) << "}";
            }
        }
        out << ']'; return copy_string(out.str());
    } catch (...) { return nullptr; }
}
// Number of bytes, starting at `start` inside file `file`, that are already downloaded without a gap.
long long strom_contiguous(void* p, int id, int file, long long start) {
    if (!p) return 0;
    try {
        auto* e=static_cast<Engine*>(p); std::lock_guard<std::mutex> lock(e->mutex);
        if (id<0 || id>=int(e->handles.size()) || !e->handles[id].is_valid()) return 0;
        auto& h = e->handles[id]; auto ti = h.torrent_file(); if (!ti) return 0;
        auto const& fs = ti->files(); if (file<0 || file>=fs.num_files()) return 0;
        auto idx = lt::file_index_t(file); long long size = fs.file_size(idx);
        if (start<0 || start>=size) return 0;
        auto st = h.status(lt::torrent_handle::query_pieces);
        if (st.is_seeding || (st.is_finished && st.pieces.empty())) return size - start;
        long long pos = start;
        while (pos < size) {
            lt::peer_request r = ti->map_file(idx, pos, 1);
            if (r.piece < lt::piece_index_t(0) || int(r.piece) >= st.pieces.size() || !st.pieces.get_bit(r.piece)) break;
            pos += ti->piece_size(r.piece) - r.start;
        }
        return std::min(pos, size) - start;
    } catch (...) { return 0; }
}
// Switches a torrent to "in order" mode and puts the chosen file first. Returns 1 when metadata is known.
int strom_stream_prepare(void* p, int id, int file) {
    if (!p) return 0;
    try {
        auto* e=static_cast<Engine*>(p); std::lock_guard<std::mutex> lock(e->mutex);
        if (id<0 || id>=int(e->handles.size()) || !e->handles[id].is_valid()) return 0;
        auto& h = e->handles[id]; auto ti = h.torrent_file(); if (!ti) return 0;
        if (file<0 || file>=ti->files().num_files()) return 0;
        h.set_flags(lt::torrent_flags::sequential_download);
        h.file_priority(lt::file_index_t(file), lt::top_priority);
        return 1;
    } catch (...) { return 0; }
}
// Asks for the pieces covering [offset, offset+bytes) of the file to be fetched next, nearest first.
int strom_stream_window(void* p, int id, int file, long long offset, long long bytes) {
    if (!p || bytes <= 0) return 0;
    try {
        auto* e=static_cast<Engine*>(p); std::lock_guard<std::mutex> lock(e->mutex);
        if (id<0 || id>=int(e->handles.size()) || !e->handles[id].is_valid()) return 0;
        auto& h = e->handles[id]; auto ti = h.torrent_file(); if (!ti) return 0;
        auto const& fs = ti->files(); if (file<0 || file>=fs.num_files()) return 0;
        auto idx = lt::file_index_t(file); long long size = fs.file_size(idx);
        long long pos = std::max<long long>(0, offset), end = std::min(size, offset + bytes); int rank = 0, count = 0;
        while (pos < end) {
            lt::peer_request r = ti->map_file(idx, pos, 1);
            if (!h.have_piece(r.piece)) { h.set_piece_deadline(r.piece, 150 * (++rank), {}); ++count; }
            pos += ti->piece_size(r.piece) - r.start;
        }
        return count;
    } catch (...) { return 0; }
}
void strom_stream_stop(void* p, int id) {
    if (!p) return; auto* e=static_cast<Engine*>(p); std::lock_guard<std::mutex> lock(e->mutex);
    if (id<0 || id>=int(e->handles.size()) || !e->handles[id].is_valid()) return;
    e->handles[id].unset_flags(lt::torrent_flags::sequential_download); e->handles[id].clear_piece_deadlines();
}
#ifdef STROM_TESTING
int strom_test_restored(void* p, int id) { auto* e=static_cast<Engine*>(p); return e->restored.at(id) ? 1 : 0; }
int strom_test_port(void* p) { return static_cast<Engine*>(p)->session.listen_port(); }
void strom_test_connect(void* p, int id, int port) {
    auto* e=static_cast<Engine*>(p);
    std::lock_guard<std::mutex> lock(e->mutex);
    e->handles.at(id).connect_peer({lt::make_address("127.0.0.1"), static_cast<unsigned short>(port)});
}
#endif
char* strom_snapshot(void* p) {
    if (!p) return nullptr;
    try {
        auto* e=static_cast<Engine*>(p); std::lock_guard<std::mutex> lock(e->mutex); e->collect(); std::ostringstream out; out << '[';
        bool first=true;
        for (int i=0; i<int(e->handles.size()); ++i) {
            if(!e->handles[i].is_valid()) continue;
            auto s=e->handles[i].status(); if(!first) out << ','; first=false;
            out << "{\"id\":" << i << ",\"name\":" << json_quote(s.name)
                << ",\"progress\":" << s.progress_ppm / 1000000.0
                << ",\"size\":" << s.total_wanted << ",\"done\":" << s.total_wanted_done
                << ",\"uploaded\":" << s.total_payload_upload
                << ",\"rate\":" << s.download_payload_rate << ",\"peers\":" << s.num_peers << ",\"seeds\":" << s.num_seeds
                << ",\"elapsed\":" << s.active_duration.count()
                << ",\"queue\":" << static_cast<int>(s.queue_position)
                << ",\"checking\":" << ((s.state == lt::torrent_status::checking_files || s.state == lt::torrent_status::checking_resume_data) ? "true" : "false")
                << ",\"complete\":" << (s.is_finished?"true":"false")
                << ",\"paused\":" << ((s.flags & lt::torrent_flags::paused)?"true":"false")
                << ",\"error\":" << json_quote(s.errc ? s.errc.message() : "") << '}';
        }
        out << ']'; return ::strdup(out.str().c_str());
    } catch (std::exception const& err) { last_error=err.what(); return nullptr; }
}
}
