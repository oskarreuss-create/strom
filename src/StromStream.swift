import Foundation
import Network

/// A tiny HTTP server for the video player. It only listens on this Mac (127.0.0.1) and only answers requests that
/// carry an unguessable token, so other programs and web pages cannot read the files. It never hands out bytes that are
/// not on disk yet: when the player asks for a part that has not arrived it waits (up to 30 s) and then gives up.
final class StromStreamServer: @unchecked Sendable {
    struct Source: Sendable {
        let fileURL: URL
        let size: Int64
        let contentType: String
        /// How many bytes, from `start`, are already on disk without a gap.
        let contiguous: @Sendable (Int64) -> Int64
    }

    private let queue = DispatchQueue(label: "ch.oskarreus.strom.stream")
    private var listener: NWListener?
    private var sources: [String: Source] = [:]
    private(set) var port: UInt16 = 0
    private static let idleLimit: TimeInterval = 30, chunk = 256 * 1024

    /// Starts listening (once) and returns the port.
    func start() async throws -> UInt16 {
        if port != 0 { return port }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        self.listener = listener
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            nonisolated(unsafe) var resumed = false
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if !resumed, let value = listener.port?.rawValue { resumed = true; self?.port = value; continuation.resume(returning: value) }
                case .failed(let error):
                    if !resumed { resumed = true; continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// Registers a file and returns the secret address for it.
    func register(_ source: Source) -> URL? {
        guard port != 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        queue.sync { sources[token] = source }
        let name = source.fileURL.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "video"
        return URL(string: "http://127.0.0.1:\(port)/v/\(token)/\(name)")
    }
    func unregister(token: String) { queue.sync { sources[token] = nil } }
    func stop() { listener?.cancel(); listener = nil; port = 0; queue.sync { sources = [:] } }

    // ---- connections ----
    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        let gotHeader = HeaderFlag()
        read(connection, buffer: Data(), gotHeader: gotHeader)
        // A client that connects and never sends its request is dropped; streaming itself has no overall time limit.
        queue.asyncAfter(deadline: .now() + 10) { if !gotHeader.done { connection.cancel() } }
    }
    private final class HeaderFlag: @unchecked Sendable { var done = false }
    private func read(_ connection: NWConnection, buffer: Data, gotHeader: HeaderFlag) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, finished, error in
            guard let self else { return }
            var buffer = buffer; if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) { gotHeader.done = true; self.handle(connection, header: String(decoding: buffer[..<end.lowerBound], as: UTF8.self)); return }
            if buffer.count > 16 * 1024 || error != nil || finished { connection.cancel(); return }
            self.read(connection, buffer: buffer, gotHeader: gotHeader)
        }
    }
    private func respond(_ connection: NWConnection, status: String, headers: [String: String] = [:], body: Data = Data(), close: Bool = true) {
        var text = "HTTP/1.1 \(status)\r\n"
        for (key, value) in headers { text += "\(key): \(value)\r\n" }
        text += "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        var out = Data(text.utf8); out.append(body)
        connection.send(content: out, completion: .contentProcessed { _ in if close { connection.cancel() } })
    }
    private func handle(_ connection: NWConnection, header: String) {
        let lines = header.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else { return respond(connection, status: "405 Method Not Allowed") }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() { if let colon = line.firstIndex(of: ":") { fields[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces) } }
        // Only a local program can have asked: the Host must be this server, and browsers (which add Origin) are refused.
        let hosts: Set<String> = ["127.0.0.1:\(port)", "localhost:\(port)"]
        guard let host = fields["host"], hosts.contains(host), fields["origin"] == nil else { return respond(connection, status: "403 Forbidden") }
        let path = String(parts[1]).split(separator: "?").first.map(String.init) ?? ""
        let pieces = path.split(separator: "/").map(String.init)
        guard pieces.count >= 2, let source = sources[pieces[1]] else { return respond(connection, status: "404 Not Found") }
        if pieces[0] == "status" {
            let prefix = source.contiguous(0)
            let json = "{\"size\":\(source.size),\"prefix\":\(prefix),\"complete\":\(prefix >= source.size)}"
            return respond(connection, status: "200 OK", headers: ["Content-Type": "application/json", "Content-Length": "\(json.utf8.count)"], body: parts[0] == "HEAD" ? Data() : Data(json.utf8))
        }
        guard pieces[0] == "v" else { return respond(connection, status: "404 Not Found") }
        var start: Int64 = 0, end = source.size - 1, ranged = false
        if let range = fields["range"], range.hasPrefix("bytes=") {
            let spec = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            if spec.count == 2 {
                ranged = true
                if spec[0].isEmpty, let suffix = Int64(spec[1]), suffix > 0 { start = max(0, source.size - suffix) }
                else if let a = Int64(spec[0]) { start = a; if let b = Int64(spec[1]) { end = min(b, source.size - 1) } }
                else { return respond(connection, status: "416 Range Not Satisfiable", headers: ["Content-Range": "bytes */\(source.size)"]) }
            }
        }
        guard start >= 0, start < source.size, end >= start else { return respond(connection, status: "416 Range Not Satisfiable", headers: ["Content-Range": "bytes */\(source.size)"]) }
        var headers = ["Content-Type": source.contentType, "Accept-Ranges": "bytes", "Content-Length": "\(end - start + 1)"]
        if ranged { headers["Content-Range"] = "bytes \(start)-\(end)/\(source.size)" }
        if parts[0] == "HEAD" { return respond(connection, status: ranged ? "206 Partial Content" : "200 OK", headers: headers) }
        guard let file = try? FileHandle(forReadingFrom: source.fileURL) else {
            // The file appears with the first piece; wait for it like for any other missing bytes.
            return pumpWithoutFile(connection, source: source, status: ranged ? "206 Partial Content" : "200 OK", headers: headers, start: start, end: end)
        }
        send(connection, head: (ranged ? "206 Partial Content" : "200 OK", headers), file: file, source: source, position: start, end: end, lastProgress: Date())
    }
    private func pumpWithoutFile(_ connection: NWConnection, source: Source, status: String, headers: [String: String], start: Int64, end: Int64, since: Date = Date()) {
        if let file = try? FileHandle(forReadingFrom: source.fileURL) {
            return send(connection, head: (status, headers), file: file, source: source, position: start, end: end, lastProgress: Date())
        }
        if Date().timeIntervalSince(since) > Self.idleLimit { return respond(connection, status: "503 Service Unavailable", headers: ["Retry-After": "2"]) }
        queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.pumpWithoutFile(connection, source: source, status: status, headers: headers, start: start, end: end, since: since) }
    }
    /// Sends the headers (once) and then the bytes, in pieces, as they become available.
    private func send(_ connection: NWConnection, head: (String, [String: String])?, file: FileHandle, source: Source, position: Int64, end: Int64, lastProgress: Date) {
        if position > end { try? file.close(); connection.cancel(); return }
        let available = source.contiguous(position)
        if available <= 0 {
            if Date().timeIntervalSince(lastProgress) > Self.idleLimit { try? file.close(); connection.cancel(); return }
            queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.send(connection, head: head, file: file, source: source, position: position, end: end, lastProgress: lastProgress) }
            return
        }
        let count = Int(min(available, end - position + 1, Int64(Self.chunk)))
        var data = Data()
        do { try file.seek(toOffset: UInt64(position)); data = try file.read(upToCount: count) ?? Data() } catch { try? file.close(); connection.cancel(); return }
        guard !data.isEmpty else { try? file.close(); connection.cancel(); return }
        var out = Data()
        if let head {
            var text = "HTTP/1.1 \(head.0)\r\n"
            for (key, value) in head.1 { text += "\(key): \(value)\r\n" }
            text += "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
            out.append(Data(text.utf8))
        }
        out.append(data)
        connection.send(content: out, completion: .contentProcessed { [weak self] error in
            if error != nil { try? file.close(); connection.cancel(); return }
            self?.send(connection, head: nil, file: file, source: source, position: position + Int64(data.count), end: end, lastProgress: Date())
        })
    }

    static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        case "ts", "m2ts", "mts": return "video/mp2t"
        default: return "application/octet-stream"
        }
    }
}
