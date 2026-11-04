import Foundation
import AppKit
import Combine

@_silgen_name("strom_create") private func engineCreate() -> UnsafeMutableRawPointer?
@_silgen_name("strom_destroy") private func engineDestroy(_ p: UnsafeMutableRawPointer?)
@_silgen_name("strom_last_error") private func engineError() -> UnsafePointer<CChar>?
@_silgen_name("strom_set_torrent_sharing") private func engineSharing(_ p: UnsafeMutableRawPointer?, _ id: Int32, _ enabled: Int32)
@_silgen_name("strom_add") private func engineAdd(_ p: UnsafeMutableRawPointer?, _ source: UnsafePointer<CChar>, _ path: UnsafePointer<CChar>, _ paused: Int32, _ resume: UnsafePointer<CChar>, _ sharing: Int32, _ allowMissingSource: Int32) -> Int32
@_silgen_name("strom_pause") private func enginePause(_ p: UnsafeMutableRawPointer?, _ id: Int32, _ paused: Int32)
@_silgen_name("strom_remove") private func engineRemove(_ p: UnsafeMutableRawPointer?, _ id: Int32)
@_silgen_name("strom_priority") private func enginePriority(_ p: UnsafeMutableRawPointer?, _ id: Int32, _ value: Int32)
@_silgen_name("strom_resume_can_replace_source") private func resumeCanReplaceSource(_ resume: UnsafePointer<CChar>, _ source: UnsafePointer<CChar>) -> Int32
@_silgen_name("strom_checkpoint") private func engineCheckpoint(_ p: UnsafeMutableRawPointer?, _ wait: Int32)
@_silgen_name("strom_snapshot") private func engineSnapshot(_ p: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("strom_free") private func engineFree(_ s: UnsafeMutablePointer<CChar>?)

struct TorrentItem: Codable, Identifiable {
    var id: Int32; var name: String; var progress: Double; var size: Int64; var done: Int64
    var rate: Int64; var peers: Int; var seeds: Int; var elapsed: Int64; var uploaded: Int64; var checking: Bool; var complete: Bool; var paused: Bool; var error: String; var safeHold: Bool? = nil
}
struct SavedTorrent: Codable {
    var source: String; var directory: String; var paused: Bool
    var stopped: Bool = false; var added: Date = Date(); var priority: Int = 3
    var peak: Int64 = 0; var speedTotal: Int64 = 0; var speedSamples: Int64 = 0; var uploaded: Int64 = 0; var downloadSeconds: Int64 = 0; var speedHistory: [Double] = []; var speedByPercent: [Double] = Array(repeating: -1, count: 101); var uploadBaselineKnown = true; var resumeID = UUID().uuidString; var sharingOverride: Bool? = nil; var ownedTorrentCopy = false; var torrentRemoved = false
    enum CodingKeys: String, CodingKey { case source, directory, paused, stopped, added, priority, peak, speedTotal, speedSamples, uploaded, downloadSeconds, speedHistory, speedByPercent, uploadBaselineKnown, resumeID, sharingOverride, ownedTorrentCopy, torrentRemoved }
    init(source: String, directory: String, paused: Bool) { self.source=source; self.directory=directory; self.paused=paused }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(String.self, forKey: .source); directory = try c.decode(String.self, forKey: .directory)
        paused = try c.decode(Bool.self, forKey: .paused); stopped = try c.decodeIfPresent(Bool.self, forKey: .stopped) ?? false
        added = try c.decodeIfPresent(Date.self, forKey: .added) ?? .distantPast; priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 3
        peak = try c.decodeIfPresent(Int64.self, forKey: .peak) ?? 0; speedTotal = try c.decodeIfPresent(Int64.self, forKey: .speedTotal) ?? 0
        speedSamples = try c.decodeIfPresent(Int64.self, forKey: .speedSamples) ?? 0
        uploaded = try c.decodeIfPresent(Int64.self, forKey: .uploaded) ?? 0
        downloadSeconds = try c.decodeIfPresent(Int64.self, forKey: .downloadSeconds) ?? 0
        speedHistory = try c.decodeIfPresent([Double].self, forKey: .speedHistory) ?? []
        let buckets = try c.decodeIfPresent([Double].self, forKey: .speedByPercent) ?? []
        speedByPercent = buckets.count == 101 ? buckets : Array(repeating: -1, count: 101)
        uploadBaselineKnown = try c.decodeIfPresent(Bool.self, forKey: .uploadBaselineKnown) ?? false
        let storedID = try c.decodeIfPresent(String.self, forKey: .resumeID) ?? ""
        resumeID = UUID(uuidString: storedID)?.uuidString ?? UUID().uuidString
        sharingOverride = try c.decodeIfPresent(Bool.self, forKey: .sharingOverride)
        ownedTorrentCopy = try c.decodeIfPresent(Bool.self, forKey: .ownedTorrentCopy) ?? false
        torrentRemoved = try c.decodeIfPresent(Bool.self, forKey: .torrentRemoved) ?? false
    }
}

@MainActor final class StromEngine: ObservableObject {
    enum DownloadEvent { case started, completed, failed }
    var onDownloadEvent: ((DownloadEvent, String) -> Void)?
    private var notifiedStarts: Set<Int32> = []
    @Published var items: [TorrentItem] = []
    @Published var errorMessage: String = ""
    @Published var errorDetail: String = ""
    @Published var showError = false
    private var handle: UnsafeMutableRawPointer?
    private var timer: Timer?
    @Published private(set) var records: [Int32: SavedTorrent] = [:]
    @Published private(set) var history: [Int32: [Double]] = [:]
    @Published private(set) var sessionSpeeds: [Int32: (total: Int64, samples: Int64)] = [:]
    func sessionAverage(for item: TorrentItem) -> Int64? {
        guard let data = sessionSpeeds[item.id], data.samples > 0 else { return nil }
        return data.total / data.samples
    }
    private var ticks = 0
    private var didFlush = false
    var plusAllowed: () -> Bool = { false }
    private var cleanupAttempted: Set<Int32> = []
    private var previousUploads: [Int32: Int64] = [:]
    private var unresolved: [SavedTorrent] = []
    private var storageHealthy = true
    private let storageKey = "strom.saved.torrents.v1"

    init() {
        handle = engineCreate()
        guard handle != nil else { report("Не удалось запустить торрент-движок."); return }
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            if let saved = try? JSONDecoder().decode([SavedTorrent].self, from: data) {
                for item in saved where !add(item.source, directory: item.directory, paused: item.paused || item.stopped, save: false, saved: item) { unresolved.append(item) }
                persist()
            } else {
                storageHealthy = false
                report("Не удалось прочитать сохранённый список загрузок. Данные сохранены без изменений.")
            }
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh(recordStatistics: true) } }
    }
    isolated deinit {
        timer?.invalidate()
        if !didFlush {
            if storageHealthy, let data = try? JSONEncoder().encode(records.sorted { $0.key < $1.key }.map(\.value) + unresolved) { UserDefaults.standard.set(data, forKey: storageKey) }
            engineCheckpoint(handle, 1)
        }
        engineDestroy(handle)
    }
    func setSharing(_ enabled: Bool) {
        for (id, record) in records where record.sharingOverride == nil { engineSharing(handle, id, enabled ? 1 : 0) }
    }
    func sharingAllowed(_ item: TorrentItem) -> Bool { records[item.id]?.sharingOverride ?? UserDefaults.standard.bool(forKey: "allowSharing") }
    func setSharing(_ enabled: Bool, for item: TorrentItem) {
        records[item.id]?.sharingOverride = enabled
        engineSharing(handle, item.id, enabled ? 1 : 0); persist()
    }
    @discardableResult func add(_ source: String, directory: String, paused: Bool = false, save: Bool = true, saved: SavedTorrent? = nil, ownedTorrentCopy: Bool = false) -> Bool {
        guard storageHealthy else { report("Список загрузок недоступен. Новые записи временно отключены."); return false }
        guard handle != nil else { report("Торрент-движок недоступен."); return false }
        var record = saved ?? SavedTorrent(source: source, directory: directory, paused: paused)
        if saved == nil { record.ownedTorrentCopy = ownedTorrentCopy }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("STRÖM/Resume", isDirectory: true)
        do { try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { report("Не удалось сохранить состояние загрузки.", detail: error.localizedDescription); return false }
        let resume = base.appendingPathComponent(record.resumeID + ".fastresume").path
        let sharing = record.sharingOverride ?? UserDefaults.standard.bool(forKey: "allowSharing")
        let id = source.withCString { s in directory.withCString { d in resume.withCString { r in engineAdd(handle, s, d, paused ? 1 : 0, r, sharing ? 1 : 0, record.torrentRemoved ? 1 : 0) } } }
        guard id >= 0 else { report("Не удалось добавить торрент.", detail: engineError().map { String(cString: $0) } ?? ""); return false }
        records[id] = record
        history[id] = records[id]?.speedHistory ?? []
        enginePriority(handle, id, Int32(records[id]?.priority ?? 3))
        if save { persist() }
        refresh()
        return true
    }
    func pause(_ item: TorrentItem) {
        let wasPaused = records[item.id]?.paused ?? false
        enginePause(handle, item.id, wasPaused ? 0 : 1)
        records[item.id]?.paused = !wasPaused; records[item.id]?.stopped = false; persist(); refresh()
    }
    func stop(_ item: TorrentItem) { enginePause(handle, item.id, 1); records[item.id]?.paused = true; records[item.id]?.stopped = true; persist(); refresh() }
    @discardableResult func remove(_ item: TorrentItem, includingData: Bool = false) -> Bool {
        guard let record = records[item.id] else { return false }
        if includingData {
            let name = item.name
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
                report("Не удалось безопасно определить скачанный файл."); return false
            }
            let directory = URL(fileURLWithPath: record.directory, isDirectory: true).standardizedFileURL
            let target = directory.appendingPathComponent(name).standardizedFileURL
            guard target.deletingLastPathComponent() == directory else { report("Не удалось безопасно определить скачанный файл."); return false }
            let shared = records.contains { id, other in
                guard id != item.id, other.directory == record.directory,
                      let otherItem = items.first(where: { $0.id == id }) else { return false }
                return otherItem.name == name
            }
            guard !shared else { report("Этот файл используется другой загрузкой."); return false }
            guard FileManager.default.fileExists(atPath: target.path) else { report("Скачанный файл не найден."); return false }
            enginePause(handle, item.id, 1)
            records[item.id]?.paused = true; persist()
            do { try FileManager.default.trashItem(at: target, resultingItemURL: nil) }
            catch { report("Не удалось переместить скачанный файл в Корзину.", detail: error.localizedDescription); refresh(); return false }
        }
        engineRemove(handle, item.id); records.removeValue(forKey: item.id); history.removeValue(forKey: item.id); previousUploads.removeValue(forKey: item.id); sessionSpeeds.removeValue(forKey: item.id); cleanupAttempted.remove(item.id); notifiedStarts.remove(item.id); persist(); refresh(); return true
    }
    private func removeCompletedTorrentCopy(_ item: TorrentItem) {
        guard plusAllowed(), UserDefaults.standard.bool(forKey: "removeTorrentAfterCompletion"), let record = records[item.id],
              record.ownedTorrentCopy, !record.torrentRemoved, !record.source.hasPrefix("magnet:"), !cleanupAttempted.contains(item.id) else { return }
        cleanupAttempted.insert(item.id)
        guard FileManager.default.fileExists(atPath: record.source) else { return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("STRÖM/Resume", isDirectory: true)
        let resume = base.appendingPathComponent(record.resumeID + ".fastresume").path
        engineCheckpoint(handle, 1)
        let valid = resume.withCString { r in record.source.withCString { s in resumeCanReplaceSource(r, s) == 1 } }
        guard valid else { report("Не удалось сохранить данные торрента; торрент-файл оставлен на месте."); return }
        records[item.id]?.torrentRemoved = true; persist()
        do { try FileManager.default.trashItem(at: URL(fileURLWithPath: record.source), resultingItemURL: nil) }
        catch { records[item.id]?.torrentRemoved = false; persist(); report("Не удалось переместить торрент-файл в Корзину.", detail: error.localizedDescription) }
    }
    func setPriority(_ value: Int, for item: TorrentItem) {
        let value = max(1, min(5, value)); records[item.id]?.priority = value
        enginePriority(handle, item.id, Int32(value)); persist()
    }
    private func persist() {
        guard storageHealthy else { return }
        let saved = records.sorted { $0.key < $1.key }.map(\.value) + unresolved
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: storageKey) }
    }
    private func refresh(recordStatistics: Bool = false) {
        guard let raw = engineSnapshot(handle) else { return }; defer { engineFree(raw) }
        if let data = String(cString: raw).data(using: .utf8), let decoded = try? JSONDecoder().decode([TorrentItem].self, from: data) {
            let previousItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            if onDownloadEvent != nil {
                for item in decoded {
                    let previous = previousItems[item.id]
                    if !item.error.isEmpty && item.error != previous?.error {
                        onDownloadEvent?(.failed, item.name)
                    } else if item.complete, let previous, !previous.complete, !previous.checking {
                        onDownloadEvent?(.completed, item.name)
                    } else if !item.complete && !item.paused && !item.checking && item.error.isEmpty && item.rate > 0 && !notifiedStarts.contains(item.id) {
                        notifiedStarts.insert(item.id)
                        onDownloadEvent?(.started, item.name)
                    }
                    if item.paused || item.complete { notifiedStarts.remove(item.id) }
                }
            }
            items = decoded
            for item in decoded where item.safeHold == true && records[item.id]?.paused == false {
                records[item.id]?.paused = true
                persist()
                report("Проверка завершённой загрузки выявила недостающие данные; загрузка приостановлена.")
            }
            guard recordStatistics else { return }
            ticks += 1
            for item in decoded {
                if var record = records[item.id] {
                    let previous = previousUploads[item.id] ?? 0
                    record.uploaded += max(0, item.uploaded - previous)
                    previousUploads[item.id] = item.uploaded
                    if !item.paused && !item.complete && !item.checking {
                        var session = sessionSpeeds[item.id] ?? (total: 0, samples: 0)
                        session.total += max(0, item.rate); session.samples += 1
                        sessionSpeeds[item.id] = session
                        record.downloadSeconds += 1
                        history[item.id, default: []].append(Double(item.rate))
                        if history[item.id, default: []].count > 120 { history[item.id]?.removeFirst() }
                        record.speedHistory = history[item.id] ?? []
                        record.peak = max(record.peak, item.rate)
                        record.speedTotal += item.rate; record.speedSamples += 1
                        let bucket = max(0, min(100, Int(item.progress * 100)))
                        record.speedByPercent[bucket] = max(record.speedByPercent[bucket], Double(item.rate))
                    }
                    records[item.id] = record
                }
            }
            for item in decoded where item.complete { removeCompletedTorrentCopy(item) }
            if ticks % 10 == 0 { persist() }
            if ticks % 30 == 0 { engineCheckpoint(handle, 0) }
        }
    }
    func report(_ message: String, detail: String = "") { errorMessage = message; errorDetail = detail; showError = true }
    func flush() { refresh(recordStatistics: true); persist(); engineCheckpoint(handle, 1); didFlush = true }
}
