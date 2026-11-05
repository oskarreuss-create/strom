import Foundation
import AppKit

struct UpdateOffer: Equatable { let version: String; let url: URL; let notes: String }
private struct UpdateReply: Decodable { let enabled: Bool; let version: String?; let url: String?; let notes: String? }

/// Asks our server whether a newer version exists. The request carries no data about the user at all.
/// A new version is never installed automatically: the user downloads it from the project's GitHub releases.
@MainActor final class StromUpdate: ObservableObject {
    @Published private(set) var offer: UpdateOffer?
    @Published private(set) var checking = false
    @Published private(set) var status = ""   // "", "latest", "failed"
    private var lastCheck = Date.distantPast

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }, b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
    /// Only links to this project's GitHub releases are ever opened, whatever the server says.
    nonisolated static func trustedURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/oskarreuss-create/strom/releases/"), !url.path.contains("..") else { return nil }
        return url
    }

    func check(endpoint: URL?, force: Bool) async {
        guard !checking, force || Date().timeIntervalSince(lastCheck) > 6 * 3600 else { return }
        guard let endpoint else { if force { status = "failed" }; return }
        checking = true; defer { checking = false }
        lastCheck = Date()
        do {
            var request = URLRequest(url: endpoint); request.timeoutInterval = 15; request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let reply = try JSONDecoder().decode(UpdateReply.self, from: data)
            let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
            if reply.enabled, let version = reply.version, let url = Self.trustedURL(reply.url), Self.isNewer(version, than: current) {
                offer = UpdateOffer(version: version, url: url, notes: reply.notes ?? ""); status = ""
            } else { offer = nil; status = force ? "latest" : "" }
        } catch { if force { status = "failed" } }
    }
}
