import AppKit
import ApplicationServices

/*
 Системное меню «Звук» (громкость, выход, режимы AirPods: прозрачность, шумоподавление…).
 Открытого API для режимов AirPods нет, поэтому нажимаем сам значок «Звук» в строке меню
 через Универсальный доступ — тот же, что нужен для клавиш громкости.
 Если значка «Звук» в строке меню нет, открываем Пункт управления.
*/
enum SoundMenu {
    @discardableResult
    static func open() -> Bool {
        guard AXIsProcessTrusted(),
              let cc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first
        else { return openSettings() }
        let app = AXUIElementCreateApplication(cc.processIdentifier)
        var items: [(id: String, el: AXUIElement)] = []
        for attr in ["AXExtrasMenuBar", kAXMenuBarAttribute as String] {
            guard let bar: AXUIElement = value(app, attr) else { continue }
            for el in (value(bar, kAXChildrenAttribute as String) as [AXUIElement]?) ?? [] {
                let id = (value(el, kAXIdentifierAttribute as String) as String?) ?? ""
                items.append((id, el))
            }
        }
        if let s = items.first(where: { $0.id.lowercased().contains("sound") }) {
            return AXUIElementPerformAction(s.el, kAXPressAction as CFString) == .success
        }
        if let c = items.first(where: { $0.id.lowercased().contains("controlcenter") }) {
            guard AXUIElementPerformAction(c.el, kAXPressAction as CFString) == .success else { return false }
            /* в Пункте управления жмём кнопку выхода звука — открывается то же меню «Звук» */
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pressSoundOutput(app) }
            return true
        }
        return openSettings()
    }

    private static func pressSoundOutput(_ app: AXUIElement) {
        var target: AXUIElement?
        func walk(_ el: AXUIElement, _ depth: Int) {
            guard depth < 9, target == nil else { return }
            let role = (value(el, kAXRoleAttribute as String) as String?) ?? ""
            let id = (value(el, kAXIdentifierAttribute as String) as String?) ?? ""
            /* кнопка выхода звука в блоке «Звук»: id controlcenter-airplay («Аудиотрансляция AirPlay») */
            if role == "AXCheckBox" || role == "AXButton", id == "controlcenter-airplay" || id.contains("sound-output") {
                target = el
                return
            }
            for k in (value(el, kAXChildrenAttribute as String) as [AXUIElement]?) ?? [] { walk(k, depth + 1) }
        }
        for w in (value(app, kAXWindowsAttribute as String) as [AXUIElement]?) ?? [] { walk(w, 0) }
        if let t = target { AXUIElementPerformAction(t, kAXPressAction as CFString) }
        else { log("кнопка выхода звука в Пункте управления не найдена") }
    }

    private static func openSettings() -> Bool {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
    }

    private static func value<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? T
    }

    static func log(_ s: String) {
        guard ProcessInfo.processInfo.environment["ISLAND_DEBUG"] != nil || CommandLine.arguments.contains("-debug") else {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Island.log")
            let line = "\(Date()) \(s)\n"
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
            else { try? line.write(to: url, atomically: true, encoding: .utf8) }
            return
        }
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    }
}
