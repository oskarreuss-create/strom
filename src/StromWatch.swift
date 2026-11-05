import Foundation
import AppKit

/// "Watch while it downloads": picks the video file, tells the engine to fetch its beginning and end first,
/// serves it to the player through the local stream server and keeps the next pieces coming.
/// The player is only allowed to use what is already downloaded (it reads the prefix; see docs/STREAMING_CONTRACT.md).
@MainActor final class StromWatch: ObservableObject {
    enum Phase: Equatable { case idle, preparing(Double), failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var title = ""
    private let server = StromStreamServer()
    private var task: Task<Void, Never>?
    private var token: String?
    private var active: (item: TorrentItem, file: Int)?
    private static let video: Set<String> = ["mp4", "m4v", "mov", "mkv", "avi", "webm", "ts", "m2ts", "mts", "mpg", "mpeg", "wmv", "flv"]

    func start(_ item: TorrentItem, engine: StromEngine, open: @escaping @MainActor (URL) -> Void) {
        stop(engine: engine)
        title = item.name; phase = .preparing(0)
        task = Task { [weak self] in await self?.run(item, engine, open) }
    }
    func cancel(engine: StromEngine) { stop(engine: engine); phase = .idle }
    func dismissFailure() { if case .failed = phase { phase = .idle } }

    private func stop(engine: StromEngine) {
        task?.cancel(); task = nil
        if let active { engine.streamStop(active.item) }
        active = nil
        if let token { server.unregister(token: token) }
        token = nil
    }

    private func run(_ item: TorrentItem, _ engine: StromEngine, _ open: @MainActor (URL) -> Void) async {
        var files: [StreamFile] = []
        for _ in 0..<180 {   // a magnet link needs a moment to learn its file list
            files = engine.streamFiles(item)
            if !files.isEmpty || Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if Task.isCancelled { return }
        guard let file = files.filter({ Self.video.contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased()) }).max(by: { $0.size < $1.size }) else { phase = .failed("novideo"); return }
        guard let directory = engine.records[item.id]?.directory, engine.streamPrepare(item, file: file.index) else { phase = .failed("failed"); return }
        active = (item, file.index)
        let fileURL = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(file.path)
        let megabyte: Int64 = 1 << 20
        let head = min(file.size, 16 * megabyte), tail = min(file.size, 4 * megabyte)
        engine.streamWindow(item, file: file.index, offset: 0, bytes: head)
        if file.size > head { engine.streamWindow(item, file: file.index, offset: file.size - tail, bytes: tail) }
        let provider = engine.streamContiguousProvider(item, file: file.index)
        do { _ = try await server.start() } catch { phase = .failed("failed"); return }
        let source = StromStreamServer.Source(fileURL: fileURL, size: file.size, contentType: StromStreamServer.contentType(for: fileURL), contiguous: provider)
        guard let url = server.register(source) else { phase = .failed("failed"); return }
        token = url.pathComponents.count > 2 ? url.pathComponents[2] : nil
        // MP4 keeps its index at the end of the file, so the player needs the tail before it can start.
        let needsTail = ["mp4", "m4v", "mov"].contains(fileURL.pathExtension.lowercased()) && file.size > 32 * megabyte
        let need = min(file.size, max(8 * megabyte, min(48 * megabyte, file.size / 50)))
        var opened = false
        while !Task.isCancelled {
            let prefix = provider(0)
            let tailReady = !needsTail || provider(file.size - 2 * megabyte) >= 2 * megabyte
            if !opened {
                phase = .preparing(min(1, Double(prefix) / Double(need)) * (tailReady ? 1 : 0.9))
                if prefix >= need && tailReady { opened = true; phase = .idle; open(url) }
            }
            if prefix >= file.size { break }
            engine.streamWindow(item, file: file.index, offset: prefix, bytes: 32 * megabyte)   // keep the next pieces coming
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        if !Task.isCancelled { engine.streamStop(item); active = nil }   // finished: normal download rules again, the address stays valid
    }
}
