import AppKit
import ApplicationServices

/*
 Обычный чат в приложении Claude (не Claude Code) не присылает событий, поэтому смотрим на его окно
 через Универсальный доступ: пока Claude отвечает, в окне есть кнопка «Остановить». Читаем только кнопки
 (роль, подпись, идентификатор) — текст переписки не трогаем.
*/
enum ClaudeChat {
    static let bundle = "com.anthropic.claudefordesktop"

    private static func value<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? T
    }

    static func appElement() -> AXUIElement? {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        /* Electron отдаёт содержимое страницы в дерево доступности только по этой просьбе */
        AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return el
    }

    /* обход кнопок окон Claude; visit возвращает true, чтобы остановиться */
    static func walkButtons(_ visit: (_ desc: String, _ id: String, _ window: String) -> Bool) {
        guard let app = appElement() else { return }
        for w in (value(app, kAXWindowsAttribute as String) as [AXUIElement]?) ?? [] {
            let title = (value(w, kAXTitleAttribute as String) as String?) ?? ""
            var stack: [(AXUIElement, Int)] = [(w, 0)]
            var seen = 0
            while let (el, depth) = stack.popLast() {
                seen += 1
                if seen > 6000 { break }
                let role = (value(el, kAXRoleAttribute as String) as String?) ?? ""
                if role == "AXButton" {
                    let d = [(value(el, kAXDescriptionAttribute as String) as String?) ?? "",
                             (value(el, kAXTitleAttribute as String) as String?) ?? ""].joined(separator: " ")
                    let id = (value(el, kAXIdentifierAttribute as String) as String?) ?? ""
                    if visit(d, id, title) { return }
                    continue
                }
                guard depth < 40 else { continue }
                for k in (value(el, kAXChildrenAttribute as String) as [AXUIElement]?) ?? [] { stack.append((k, depth + 1)) }
            }
        }
    }

    /* кнопка «Остановить» в окне Claude — значит, Claude сейчас отвечает */
    /* только кнопка чата «Остановить ответ» / «Stop response»: у Claude Code своя кнопка «Остановить»,
       а строки действий могут содержать слово stop — их не считаем */
    static func isStop(_ d: String) -> Bool {
        let s = d.trimmingCharacters(in: .whitespaces).lowercased()
        return s == "остановить ответ" || s == "stop response" || s == "stop generating"
    }

    /* отвечает ли сейчас Claude в своём окне (ищем кнопку «Остановить ответ») */
    static func answering() -> Bool {
        var found = false
        walkButtons { d, _, _ in if isStop(d) { found = true; return true }; return false }
        return found
    }

    /* для отладки: записать в журнал только кнопки остановки (без текста переписки) */
    static func dump() {
        var lines: [String] = []
        walkButtons { d, id, w in if isStop(d) { lines.append("[\(w)] \(d) #\(id)") }; return false }
        SoundMenu.log("claude stop buttons (\(lines.count)): " + lines.joined(separator: " | "))
    }
}
