import Foundation

/*
 Командный режим: тот же бинарник шлёт событие в запущенный остров и сразу выходит.
   Island hook                 — хук Claude Code (JSON события на stdin)
   Island notify "Заголовок" "Текст"  — своё уведомление из любого скрипта
*/
enum CLI {
    static let event = Notification.Name("local.gaad.island.event")

    static func run(_ args: [String]) -> Never {
        var info: [String: String]
        switch args.first {
        case "hook":
            info = hook()
        case "notify":
            info = ["event": "Notify",
                    "title": args.count > 1 ? args[1] : "Остров",
                    "message": args.count > 2 ? args[2] : "",
                    "bundle": ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? ""]
        default:
            FileHandle.standardError.write("Island hook | Island notify \"Заголовок\" \"Текст\"\n".data(using: .utf8)!)
            exit(1)
        }
        DistributedNotificationCenter.default().postNotificationName(event, object: nil, userInfo: info, deliverImmediately: true)
        exit(0)
    }

    static func hook() -> [String: String] {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let ev = j["hook_event_name"] as? String ?? ""
        var info: [String: String] = [
            "event": ev,
            "session": j["session_id"] as? String ?? "",
            "cwd": j["cwd"] as? String ?? "",
            "message": j["message"] as? String ?? "",
            /* приложение, из которого запущен Claude Code: Терминал, Claude, VS Code… */
            "bundle": ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? "",
        ]
        if ev == "PreToolUse" {
            info["action"] = action(tool: j["tool_name"] as? String ?? "", input: j["tool_input"] as? [String: Any] ?? [:])
        }
        if ev == "Stop", let tp = j["transcript_path"] as? String {
            info["summary"] = lastAssistantText(tp)
        }
        return info
    }

    /* Что сейчас делает Claude — коротко, по-русски. */
    static func action(tool: String, input: [String: Any]) -> String {
        func file(_ k: String = "file_path") -> String {
            URL(fileURLWithPath: input[k] as? String ?? "").lastPathComponent
        }
        func short(_ s: String, _ n: Int = 46) -> String {
            let t = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            return t.count > n ? String(t.prefix(n)) + "…" : t
        }
        switch tool {
        case "Bash":
            if let d = input["description"] as? String, !d.isEmpty { return short(d) }
            return "Запускаю " + short(input["command"] as? String ?? "", 36)
        case "Edit", "MultiEdit": return "Правлю " + file()
        case "Write": return "Пишу " + file()
        case "Read": return "Читаю " + file()
        case "NotebookEdit": return "Правлю " + file("notebook_path")
        case "Grep": return "Ищу «" + short(input["pattern"] as? String ?? "", 28) + "»"
        case "Glob": return "Ищу файлы " + short(input["pattern"] as? String ?? "", 28)
        case "WebSearch": return "Ищу в сети: " + short(input["query"] as? String ?? "", 30)
        case "WebFetch": return "Читаю страницу " + (URL(string: input["url"] as? String ?? "")?.host ?? "")
        case "Task", "Agent": return "Помощник: " + short(input["description"] as? String ?? "работает", 34)
        case "TodoWrite": return "Обновляю план"
        case "AskUserQuestion": return "Задаю вопрос"
        case "Skill": return "Навык " + (input["skill"] as? String ?? "")
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_").filter { !$0.isEmpty }
                return "Инструмент " + (parts.last.map(String.init) ?? tool)
            }
            return tool
        }
    }

    /* Последний текстовый ответ ассистента из транскрипта (JSONL), коротко и без разметки. */
    static func lastAssistantText(_ path: String) -> String {
        guard let fh = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        try? fh.seek(toOffset: size > 600_000 ? size - 600_000 : 0)
        let data = (try? fh.readToEnd()) ?? Data()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n").reversed() {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  o["type"] as? String == "assistant",
                  let msg = o["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { continue }
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: " ")
            if !text.isEmpty { return clean(text) }
        }
        return ""
    }

    static func clean(_ s: String) -> String {
        var t = s
        for ch in ["**", "`", "#", "|", "> ", "- "] { t = t.replacingOccurrences(of: ch, with: " ") }
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        t = t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return t.count > 220 ? String(t.prefix(220)) + "…" : t
    }
}
