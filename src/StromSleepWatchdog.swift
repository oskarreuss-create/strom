import Foundation
import Darwin

let label = "ch.strom.sleep-recovery"
let marker = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/STRÖM/sleep-owner.json")
let agent = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
let gui = "gui/\(getuid())"
func run(_ program: String, _ arguments: [String]) -> (Int32, String) {
    let process = Process(); process.executableURL = URL(fileURLWithPath: program); process.arguments = arguments
    let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
    do { try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "") } catch { return (-1, "") }
}
func status() -> Int? {
    let result = run("/usr/bin/pmset", ["-g"])
    guard result.0 == 0 else { return nil }
    for line in result.1.components(separatedBy: .newlines) {
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        if fields.count >= 2 && fields[0] == "SleepDisabled" { return Int(fields[1]) }
    }
    return nil
}
func restoreIfOwned(requireDead: Bool) -> Bool {
    guard let data = try? Data(contentsOf: marker), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let owner = object["pid"] as? Int32 else { return !FileManager.default.fileExists(atPath: marker.path) }
    if requireDead && kill(owner, 0) == 0 { return true }
    if status() == 1 && run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", "0"]).0 != 0 { return false }
    guard status() == 0 else { return false }
    try? FileManager.default.removeItem(at: marker)
    return !FileManager.default.fileExists(atPath: marker.path)
}
func setupRecovery() -> Bool {
    do {
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = ["Label":label, "ProgramArguments":[CommandLine.arguments[0], "--recover"], "RunAtLoad":true, "ProcessType":"Background"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: agent, options: .atomic)
        let existing = run("/bin/launchctl", ["print", "\(gui)/\(label)"]).0 == 0
        return existing || run("/bin/launchctl", ["bootstrap", gui, agent.path]).0 == 0
    } catch { return false }
}
func removeRecovery() {
    try? FileManager.default.removeItem(at: agent)
    _ = run("/bin/launchctl", ["bootout", "\(gui)/\(label)"])
}
if CommandLine.arguments.contains("--recover") {
    guard FileManager.default.fileExists(atPath: marker.path) else { exit(0) }
    guard let data = try? Data(contentsOf: marker), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let owner = object["pid"] as? Int32 else { exit(1) }
    if kill(owner, 0) == 0 { exit(0) }
    if restoreIfOwned(requireDead: true) { removeRecovery() }
    exit(0)
}
guard CommandLine.arguments.contains("--watch") else { exit(2) }
guard run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "disablesleep", "1"]).0 == 0,
      run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "disablesleep", "0"]).0 == 0 else { print("ERROR:permissions"); fflush(stdout); exit(3) }
guard !FileManager.default.fileExists(atPath: marker.path) else { print("ERROR:recovery"); fflush(stdout); exit(4) }
guard setupRecovery() else { print("ERROR:recovery"); fflush(stdout); exit(5) }
var owned = false
func acquireIfNeeded() -> Bool {
    guard let current = status() else { return false }
    if current == 1 { return true }
    guard current == 0 else { return false }
    let payload: [String: Any] = ["pid": getpid()]
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }
    let fd = open(marker.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { return false }
    let wrote = data.withUnsafeBytes { ptr in write(fd, ptr.baseAddress, data.count) }; _ = close(fd)
    guard wrote == data.count else { try? FileManager.default.removeItem(at: marker); return false }
    owned = true
    return run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", "1"]).0 == 0 && status() == 1
}
if !acquireIfNeeded() {
    if owned && restoreIfOwned(requireDead: false) { removeRecovery() } else if !owned { removeRecovery() }
    print("ERROR:power"); fflush(stdout); exit(6)
}
print("ACTIVE"); fflush(stdout)
var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN | POLLHUP), revents: 0)
while true {
    pfd.revents = 0
    let result = poll(&pfd, 1, 5000)
    if result > 0 && (pfd.revents & Int16(POLLIN | POLLHUP | POLLERR)) != 0 { var byte: UInt8 = 0; if read(STDIN_FILENO, &byte, 1) <= 0 { break } }
    if getppid() == 1 { break }
    if status() == 0 {
        let ok = owned ? (run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", "1"]).0 == 0 && status() == 1) : acquireIfNeeded()
        if !ok { print("ERROR:power"); fflush(stdout); break }
    }
}
if owned {
    if restoreIfOwned(requireDead: false) { removeRecovery() } else { print("ERROR:restore"); fflush(stdout) }
} else { removeRecovery() }
