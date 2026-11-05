import Foundation
import AppKit

/// Optional, anonymous usage counters. Nothing is counted or sent unless the user allowed it
/// (UserDefaults "statsEnabled", off by default). Only totals are kept: no file names, links, e-mail,
/// license key or IP address. The installation number is random and is not linked to the license.
@MainActor final class StromUsage: ObservableObject {
    private let defaults = UserDefaults.standard
    private var lastDone: [Int32: Int64] = [:], lastUploaded: [Int32: Int64] = [:], wasComplete: [Int32: Bool] = [:]
    private var lastTick = Date()
    private var lastSend = Date.distantPast
    private var launchedCounted = false
    private var dirty = false

    var enabled: Bool { defaults.bool(forKey: "statsEnabled") }

    private var installID: String {
        if let saved = defaults.string(forKey: "usage.installID"), saved.count == 32 { return saved }
        let fresh = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        defaults.set(fresh, forKey: "usage.installID")
        return fresh
    }
    private func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
    private func number(_ key: String) -> Int64 { Int64(defaults.integer(forKey: key)) }
    private func add(_ key: String, _ value: Int64) { guard value > 0 else { return }; defaults.set(Int(number(key) + value), forKey: key); dirty = true }

    /// Switching statistics off also forgets everything that was counted but not yet sent.
    func reset() {
        for key in ["usage.launches", "usage.seconds", "usage.downloads", "usage.bytesDown", "usage.bytesUp", "usage.day"] { defaults.removeObject(forKey: key) }
        lastDone = [:]; lastUploaded = [:]; wasComplete = [:]; dirty = false
    }

    func noteLaunch() {
        guard enabled, !launchedCounted else { return }
        launchedCounted = true; rollDay(); add("usage.launches", 1)
    }

    /// Counters belong to one UTC day; a new day starts from zero.
    private func rollDay() {
        let day = today()
        if defaults.string(forKey: "usage.day") != day {
            for key in ["usage.launches", "usage.seconds", "usage.downloads", "usage.bytesDown", "usage.bytesUp"] { defaults.removeObject(forKey: key) }
            defaults.set(day, forKey: "usage.day"); dirty = true
            if launchedCounted { add("usage.launches", 1) }
        }
    }

    func tick(_ items: [TorrentItem]) {
        guard enabled else { lastDone = [:]; lastUploaded = [:]; wasComplete = [:]; lastTick = Date(); return }
        rollDay()
        let now = Date(), seconds = min(30, max(0, now.timeIntervalSince(lastTick))); lastTick = now
        if NSApp.isActive { add("usage.seconds", Int64(seconds)) }
        for item in items {
            if let before = lastDone[item.id], item.done > before { add("usage.bytesDown", item.done - before) }
            if let before = lastUploaded[item.id], item.uploaded > before { add("usage.bytesUp", item.uploaded - before) }
            if wasComplete[item.id] == false, item.complete { add("usage.downloads", 1) }
            lastDone[item.id] = item.done; lastUploaded[item.id] = item.uploaded; wasComplete[item.id] = item.complete
        }
    }

    func sendIfDue(_ license: StromLicense, language: String) async {
        guard enabled, dirty, Date().timeIntervalSince(lastSend) > 1800 else { return }
        lastSend = Date()
        let info = Bundle.main.infoDictionary ?? [:], os = ProcessInfo.processInfo.operatingSystemVersion
        let report: [String: Any] = [
            "install": installID, "day": defaults.string(forKey: "usage.day") ?? today(),
            "launches": number("usage.launches"), "activeSeconds": number("usage.seconds"), "downloads": number("usage.downloads"),
            "bytesDown": number("usage.bytesDown"), "bytesUp": number("usage.bytesUp"),
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "unknown", "os": "\(os.majorVersion).\(os.minorVersion)", "lang": language
        ]
        if await license.sendStats(report) { dirty = false }
    }
}
