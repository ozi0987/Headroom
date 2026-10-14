import Foundation

/// Claude Code の「ステータスライン」との連携。
///
/// Claude Code は、ステータスラインに設定したスクリプトへ、セッションの情報を JSON で渡す。
/// Pro / Max プランでは、その中に使用量（rate_limits）が含まれる。
/// このアプリは、その使用量だけをファイルに保存するスクリプトを登録し、ファイルを読む。
/// ログイン情報には一切触れず、Anthropic のサーバーとも通信しない。
struct StatusLineBridge {
    enum State: Equatable {
        case notConnected
        case connected
    }

    enum BridgeError: LocalizedError {
        case unreadableSettings

        var errorDescription: String? {
            switch self {
            case .unreadableSettings:
                "Claude Code の設定ファイル（~/.claude/settings.json）を読み取れませんでした。書式を確認してください。"
            }
        }
    }

    let supportDirectory: URL
    let settingsURL: URL

    static let live = StatusLineBridge(
        supportDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Headroom", directoryHint: .isDirectory),
        settingsURL: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")
    )

    /// セッションごとの保存先。複数の Claude Code を開いていても、互いに上書きしない
    var sessionsDirectory: URL { supportDirectory.appending(path: "sessions", directoryHint: .isDirectory) }
    /// 旧バージョンの保存先（1ファイルに上書きしていた）
    private var legacyStatusFileURL: URL { supportDirectory.appending(path: "status.json") }
    var scriptURL: URL { supportDirectory.appending(path: "statusline.sh") }
    var previousCommandURL: URL { supportDirectory.appending(path: "previous-statusline.txt") }
    var backupURL: URL { settingsURL.deletingLastPathComponent().appending(path: "settings.json.headroom-backup") }

    /// settings.json に書き込むコマンド。$HOME はシェルが展開するので、ユーザー名に依存しない
    static let command = #"sh "$HOME/Library/Application Support/Headroom/statusline.sh""#

    // MARK: - 状態

    var state: State {
        guard let settings = try? readSettings(),
              let statusLine = settings["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String
        else { return .notConnected }
        return Self.isOurs(command) ? .connected : .notConnected
    }

    static func isOurs(_ command: String) -> Bool {
        command.contains("Headroom/statusline.sh")
    }

    /// 保存ファイルのうち最も新しい更新日時。変化がなければ読み直さなくてよい
    func latestModification() -> Date? {
        sessionFiles().compactMap(\.modified).max()
    }

    /// 全セッションの保存ファイルをまとめた使用量。まだ一度も受け取っていなければ nil
    func readStatus(now: Date = Date()) -> MergedStatus? {
        var statuses: [StatusFile] = []
        for file in sessionFiles() {
            // 終わったセッションのファイルは、1週間たてば使い道がないので消す
            if let modified = file.modified, now.timeIntervalSince(modified) > Self.sessionRetention {
                try? FileManager.default.removeItem(at: file.url)
                continue
            }
            if let data = try? Data(contentsOf: file.url),
               let status = try? JSONDecoder().decode(StatusFile.self, from: data) {
                statuses.append(status)
            }
        }
        return MergedStatus.merge(statuses)
    }

    private static let sessionRetention: TimeInterval = 8 * 24 * 3600

    private func sessionFiles() -> [(url: URL, modified: Date?)] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles
        )) ?? []
        return urls.filter { $0.pathExtension == "json" }.map { url in
            (url, try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        }
    }

    // MARK: - 連携・解除

    /// ステータスラインにスクリプトを登録する。
    /// 元の settings.json はバックアップし、すでに設定されていたステータスラインは引き続き表示されるようにする。
    func connect() throws {
        try installScript()
        var settings = try readSettings() ?? [:]
        try backupSettings()

        var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
        if let previous = statusLine["command"] as? String, !Self.isOurs(previous) {
            try previous.write(to: previousCommandURL, atomically: true, encoding: .utf8)
        }
        statusLine["type"] = "command"
        statusLine["command"] = Self.command
        settings["statusLine"] = statusLine
        try writeSettings(settings)
    }

    /// 連携を解除し、連携前のステータスラインに戻す
    func disconnect() throws {
        guard var settings = try readSettings(),
              var statusLine = settings["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String, Self.isOurs(command)
        else { return }

        if let previous = try? String(contentsOf: previousCommandURL, encoding: .utf8), !previous.isEmpty {
            statusLine["command"] = previous
            settings["statusLine"] = statusLine
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try writeSettings(settings)
        try? FileManager.default.removeItem(at: previousCommandURL)
    }

    /// アプリの更新でスクリプトの中身が変わっても追従できるよう、連携中は起動のたびに書き直す
    func installScript() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: legacyStatusFileURL)
    }

    // MARK: - settings.json

    /// ファイルがなければ nil。あるのに JSON として読めなければエラー（壊さないよう書き込まない）
    private func readSettings() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let data = try Data(contentsOf: settingsURL)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BridgeError.unreadableSettings
        }
        return object
    }

    private func backupSettings() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.copyItem(at: settingsURL, to: backupURL)
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    // MARK: - スクリプト

    /// Claude Code から渡された JSON のうち、使用量（rate_limits）だけを保存する。
    /// 会話の内容・フォルダの場所・ログイン情報などは保存しない。
    /// macOS 標準の plutil だけを使うので、jq などの追加インストールは不要。
    static let script = #"""
    #!/bin/sh
    # Headroom: Claude Code のステータスラインから使用量（rate_limits）だけを保存する。
    # 会話の内容やフォルダの場所、ログイン情報は保存しない。
    # 使用量はそのセッションが最後に返答を受け取った時点の値なので、
    # 古い値で上書きし合わないよう、セッションごとに別のファイルへ保存する（まとめるのはアプリ側）。
    DIR="$HOME/Library/Application Support/Headroom"
    input=$(cat)

    limits=$(printf '%s' "$input" | /usr/bin/plutil -extract rate_limits json -o - - 2>/dev/null)
    if [ -n "$limits" ]; then
        sid=$(printf '%s' "$input" | /usr/bin/plutil -extract session_id raw -o - - 2>/dev/null | tr -cd 'A-Za-z0-9_-')
        [ -n "$sid" ] || sid=unknown
        mkdir -p "$DIR/sessions"
        tmp="$DIR/sessions/.$sid.$$"
        printf '{"updated_at":%s,"rate_limits":%s}' "$(date +%s)" "$limits" > "$tmp" && mv -f "$tmp" "$DIR/sessions/$sid.json"
    fi

    # 連携前に使っていたステータスラインがあれば、同じ情報を渡してその表示を使う
    if [ -s "$DIR/previous-statusline.txt" ]; then
        printf '%s' "$input" | /bin/sh -c "$(cat "$DIR/previous-statusline.txt")"
        exit $?
    fi

    # なければ使用率を短く表示する
    [ -n "$limits" ] || exit 0
    s=$(printf '%s' "$limits" | /usr/bin/plutil -extract five_hour.used_percentage raw -o - - 2>/dev/null)
    w=$(printf '%s' "$limits" | /usr/bin/plutil -extract seven_day.used_percentage raw -o - - 2>/dev/null)
    line="Headroom"
    [ -n "$s" ] && line="$line  セッション $(printf '%.0f' "$s")%"
    [ -n "$w" ] && line="$line  今週 $(printf '%.0f' "$w")%"
    printf '%s\n' "$line"
    """#
}
