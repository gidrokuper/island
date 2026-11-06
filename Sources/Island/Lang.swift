import Foundation

/*
 Язык интерфейса: русский или английский.
 По умолчанию — как в системе (русский, если он первый в списке языков, иначе английский).
 Переключается в меню острова (правый клик) или: defaults write local.gaad.island lang en|ru
*/
enum Lang {
    static var russian: Bool {
        switch UserDefaults.standard.string(forKey: "lang") {
        case "ru": return true
        case "en": return false
        default: return Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
        }
    }
    static var locale: Locale { Locale(identifier: russian ? "ru_RU" : "en_US") }
}

/* Строка на двух языках: L("Готово", "Done") */
func L(_ ru: String, _ en: String) -> String { Lang.russian ? ru : en }
