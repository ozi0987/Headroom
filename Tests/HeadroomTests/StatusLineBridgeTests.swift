import Foundation
import Testing
@testable import Headroom

/// 本物の ~/.claude には触れず、一時フォルダで確認する
struct StatusLineBridgeTests {
    let root: URL
    let bridge: StatusLineBridge

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "headroom-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        bridge = StatusLineBridge(
            supportDirectory: root.appending(path: "Library/Application Support/Headroom"),
            settingsURL: root.appending(path: ".claude/settings.json")
        )
    }

    func writeSettings(_ json: String) throws {
        try FileManager.default.createDirectory(at: bridge.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: bridge.settingsURL, atomically: true, encoding: .utf8)
    }

    func settings() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: bridge.settingsURL)) as! [String: Any]
    }

    @Test func 設定ファイルがなくても連携できる() throws {
        #expect(bridge.state == .notConnected)
        try bridge.connect()
        #expect(bridge.state == .connected)
        let statusLine = try settings()["statusLine"] as? [String: Any]
        #expect(statusLine?["command"] as? String == StatusLineBridge.command)
        #expect(FileManager.default.fileExists(atPath: bridge.scriptURL.path))
    }

    @Test func ほかの設定は残しバックアップを取る() throws {
        try writeSettings(#"{"model":"opus","permissions":{"allow":["Bash(ls)"]}}"#)
        try bridge.connect()
        let after = try settings()
        #expect(after["model"] as? String == "opus")
        #expect((after["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls)"])
        #expect(FileManager.default.fileExists(atPath: bridge.backupURL.path))
    }

    @Test func 解除で何もなかった状態に戻る() throws {
        try writeSettings(#"{"model":"opus"}"#)
        try bridge.connect()
        try bridge.disconnect()
        let after = try settings()
        #expect(after["statusLine"] == nil)
        #expect(after["model"] as? String == "opus")
        #expect(bridge.state == .notConnected)
    }

    @Test func 元のステータスラインは解除で戻る() throws {
        try writeSettings(#"{"statusLine":{"type":"command","command":"~/my-line.sh","padding":0}}"#)
        try bridge.connect()
        #expect(try String(contentsOf: bridge.previousCommandURL, encoding: .utf8) == "~/my-line.sh")
        // padding など、ほかの項目はそのまま
        #expect((try settings()["statusLine"] as? [String: Any])?["padding"] as? Int == 0)

        try bridge.disconnect()
        let statusLine = try settings()["statusLine"] as? [String: Any]
        #expect(statusLine?["command"] as? String == "~/my-line.sh")
        #expect(!FileManager.default.fileExists(atPath: bridge.previousCommandURL.path))
    }

    @Test func 二回連携しても元のステータスラインを失わない() throws {
        try writeSettings(#"{"statusLine":{"type":"command","command":"~/my-line.sh"}}"#)
        try bridge.connect()
        try bridge.connect()
        #expect(try String(contentsOf: bridge.previousCommandURL, encoding: .utf8) == "~/my-line.sh")
    }

    @Test func 読めない設定ファイルは書き換えない() throws {
        let broken = #"{"model": "opus",,}"#
        try writeSettings(broken)
        #expect(throws: StatusLineBridge.BridgeError.self) { try bridge.connect() }
        #expect(try String(contentsOf: bridge.settingsURL, encoding: .utf8) == broken)
    }

    func writeSession(_ id: String, _ json: String) throws {
        try FileManager.default.createDirectory(at: bridge.sessionsDirectory, withIntermediateDirectories: true)
        try json.write(to: bridge.sessionsDirectory.appending(path: "\(id).json"), atomically: true, encoding: .utf8)
    }

    @Test func 保存ファイルを読める() throws {
        let json = #"{"updated_at":1738425000,"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}"#
        try writeSession("a", json)
        let status = try #require(bridge.readStatus(now: Date(timeIntervalSince1970: 1738425000)))
        #expect(status.snapshot.session?.percent == 23.5)
        #expect(status.snapshot.weekly?.resetsAt == Date(timeIntervalSince1970: 1738857600))
        #expect(status.updatedAt == Date(timeIntervalSince1970: 1738425000))
    }

    @Test func 放置中のセッションの古い値に引きずられない() throws {
        // 実際に起きたこと：使っているセッションは 54%、放置していたセッションは1時間以上前の 30% を持っていた
        try writeSession("active", #"{"updated_at":1791137829,"rate_limits":{"five_hour":{"used_percentage":54,"resets_at":1791139800},"seven_day":{"used_percentage":41,"resets_at":1791280800}}}"#)
        try writeSession("idle", #"{"updated_at":1791137900,"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":1791139800},"seven_day":{"used_percentage":38,"resets_at":1791280800}}}"#)
        let status = try #require(bridge.readStatus(now: Date(timeIntervalSince1970: 1791137900)))
        #expect(status.snapshot.session?.percent == 54)
        #expect(status.snapshot.weekly?.percent == 41)
    }

    @Test func 一週間以上前のセッションのファイルは消す() throws {
        try writeSession("old", #"{"updated_at":1,"rate_limits":{}}"#)
        let later = Date().addingTimeInterval(9 * 24 * 3600)
        _ = bridge.readStatus(now: later)
        #expect(!FileManager.default.fileExists(atPath: bridge.sessionsDirectory.appending(path: "old.json").path))
    }
}

struct MergedStatusTests {
    func window(_ percent: Double, resetsAt: Double?) -> UsageWindow {
        UsageWindow(percent: percent, resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)))
    }

    @Test func 同じ周期なら使用率が高いほう() {
        let result = MergedStatus.latest([window(30, resetsAt: 7200), window(54, resetsAt: 7200)])
        #expect(result?.percent == 54)
    }

    @Test func 新しい周期の値が優先される() {
        // リセット後の新しい周期（5%）と、リセット前の周期を持ったままのセッション（90%）
        let result = MergedStatus.latest([window(90, resetsAt: 3600), window(5, resetsAt: 3600 + 5 * 3600)])
        #expect(result?.percent == 5)
    }

    @Test func 秒のぶれは同じ周期とみなす() {
        let result = MergedStatus.latest([window(40, resetsAt: 7200), window(45, resetsAt: 7201)])
        #expect(result?.percent == 45)
    }

    @Test func 値のないセッションは無視する() {
        #expect(MergedStatus.latest([nil, window(20, resetsAt: 7200)])?.percent == 20)
        #expect(MergedStatus.latest([nil, nil]) == nil)
    }
}

/// 実際に sh でスクリプトを動かして確認する（HOME を一時フォルダに差し替える）
struct StatusLineScriptTests {
    let home: URL

    init() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "headroom-script-\(UUID().uuidString)")
        let dir = home.appending(path: "Library/Application Support/Headroom")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try StatusLineBridge.script.write(to: dir.appending(path: "statusline.sh"), atomically: true, encoding: .utf8)
    }

    var dir: URL { home.appending(path: "Library/Application Support/Headroom") }

    func run(_ input: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", StatusLineBridge.command]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(input.data(using: .utf8)!)
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        return String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    let sample = #"{"session_id":"abc-123","model":{"display_name":"Opus"},"cwd":"/secret/project","transcript_path":"/secret/t.jsonl","rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}"#

    @Test func 使用量だけを保存し短く表示する() throws {
        let output = try run(sample)
        #expect(output == "Headroom  セッション 24%  今週 41%\n")
        let saved = try String(contentsOf: dir.appending(path: "sessions/abc-123.json"), encoding: .utf8)
        #expect(saved.contains("rate_limits"))
        // 会話やフォルダの情報は保存しない
        #expect(!saved.contains("secret"))
        #expect(!saved.contains("Opus"))
    }

    @Test func 使用量がなければ保存しない() throws {
        _ = try run(#"{"model":{"display_name":"Opus"}}"#)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "sessions").path))
    }

    @Test func セッションIDの記号はファイル名に使わない() throws {
        _ = try run(#"{"session_id":"../../evil","rate_limits":{"five_hour":{"used_percentage":1}}}"#)
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "sessions/evil.json").path))
    }

    @Test func 元のステータスラインの表示を使う() throws {
        try #"cat > /dev/null; echo "my line""#.write(to: dir.appending(path: "previous-statusline.txt"), atomically: true, encoding: .utf8)
        let output = try run(sample)
        #expect(output == "my line\n")
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "sessions/abc-123.json").path))
    }
}
