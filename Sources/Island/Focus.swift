import AppKit
import SwiftUI

struct FocusMode: Equatable {
    var id: String
    var name: String
    var symbol: String
    var tint: String
}

/*
 Режим фокуса (Сон, Не беспокоить, Работа…). macOS не даёт его обычным приложениям,
 поэтому читаем файлы ~/Library/DoNotDisturb/DB — для этого острову нужен «Полный доступ к диску».
*/
final class FocusWatcher {
    var onChange: ((FocusMode?, FocusMode?) -> Void)?
    private(set) var current: FocusMode?
    private(set) var readable = true
    private var stamp: Date?

    private let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")

    func start() {
        current = read()
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let url = dir.appendingPathComponent("Assertions.json")
        let m = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard m != stamp else { return }
        stamp = m
        let new = read()
        if new != current {
            let old = current
            current = new
            onChange?(new, old)
        }
    }

    private func json(_ name: String) -> [String: Any]? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private func read() -> FocusMode? {
        guard let a = json("Assertions.json") else { readable = false; return nil }
        readable = true
        let records = (a["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]] ?? []
        guard let id = records.compactMap({
            ($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String
        }).last else { return nil }

        var mode = FocusMode(id: id, name: Self.fallbackName(id), symbol: Self.fallbackSymbol(id), tint: "")
        if let c = json("ModeConfigurations.json"),
           let confs = (c["data"] as? [[String: Any]])?.first?["modeConfigurations"] as? [String: Any],
           let m = (confs[id] as? [String: Any])?["mode"] as? [String: Any] {
            if let n = m["name"] as? String, !n.isEmpty { mode.name = n }
            if let s = m["symbolImageName"] as? String, !s.isEmpty { mode.symbol = s }
            if let t = m["tintColorName"] as? String { mode.tint = t }
        }
        return mode
    }

    static func fallbackSymbol(_ id: String) -> String {
        if id.contains("sleep") { return "bed.double.fill" }
        if id.contains("work") { return "briefcase.fill" }
        if id.contains("personal") { return "person.fill" }
        if id.contains("driving") { return "car.fill" }
        if id.contains("fitness") { return "figure.run" }
        if id.contains("gaming") { return "gamecontroller.fill" }
        if id.contains("reading") { return "book.fill" }
        if id.contains("mindfulness") { return "apple.meditate" }
        return "moon.fill"
    }

    static func fallbackName(_ id: String) -> String {
        if id.contains("sleep") { return L("Сон", "Sleep") }
        if id.contains("work") { return L("Работа", "Work") }
        if id.contains("personal") { return L("Личное", "Personal") }
        if id.contains("driving") { return L("Вождение", "Driving") }
        if id.contains("fitness") { return L("Фитнес", "Fitness") }
        if id.contains("gaming") { return L("Игры", "Gaming") }
        if id.contains("reading") { return L("Чтение", "Reading") }
        return L("Не беспокоить", "Do Not Disturb")
    }

    static func color(_ tint: String, id: String) -> Color {
        switch tint {
        case "systemIndigoColor": return .indigo
        case "systemPurpleColor": return .purple
        case "systemTealColor": return .teal
        case "systemMintColor": return .mint
        case "systemCyanColor": return .cyan
        case "systemBlueColor": return .blue
        case "systemGreenColor": return .green
        case "systemOrangeColor": return .orange
        case "systemPinkColor": return .pink
        case "systemRedColor": return .red
        case "systemYellowColor": return .yellow
        case "systemBrownColor": return .brown
        default: return id.contains("sleep") ? .teal : .indigo
        }
    }

    static func openPrivacySettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(u)
        }
    }
}
