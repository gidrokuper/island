import Foundation

/* Настройки острова (меню по правому клику). Хранятся в UserDefaults приложения. */
enum Prefs {
    private static let d = UserDefaults.standard
    private static func get<T>(_ k: String, _ def: T) -> T { d.object(forKey: k) as? T ?? def }

    /* непрозрачность фона: 1 — без прозрачности */
    static var opacity: Double { get { get("opacity", 0.78) } set { d.set(newValue, forKey: "opacity") } }
    /* уведомления других приложений (Telegram и т. д.) */
    static var appNotices: Bool { get { get("appNotices", true) } set { d.set(newValue, forKey: "appNotices") } }
    /* уведомления Claude Code: готово, нужен ответ */
    static var claudeNotices: Bool { get { get("claudeNotices", true) } set { d.set(newValue, forKey: "claudeNotices") } }
    /* беззвучные уведомления (заглушённые чаты и т. п.) показывать в острове */
    static var silentNotices: Bool { get { get("silentNotices", false) } set { d.set(newValue, forKey: "silentNotices") } }
    /* показывать, когда отвечает обычный чат Claude (через Универсальный доступ) */
    static var claudeChat: Bool { get { get("claudeChat", true) } set { d.set(newValue, forKey: "claudeChat") } }
    /* в режиме фокуса уведомления не показывать */
    static var quietInFocus: Bool { get { get("quietInFocus", true) } set { d.set(newValue, forKey: "quietInFocus") } }
    /* сколько секунд уведомление на экране */
    static var noticeSeconds: Double { get { get("noticeSeconds", 6.0) } set { d.set(newValue, forKey: "noticeSeconds") } }
    /* показывать музыку у выреза */
    static var showMusic: Bool { get { get("showMusic", true) } set { d.set(newValue, forKey: "showMusic") } }
    /* откуда брать музыку: all, spotify, music */
    static var musicSource: String { get { get("musicSource", "all") } set { d.set(newValue, forKey: "musicSource") } }
    /* справа от выреза при музыке: spark — искра Claude, bars — эквалайзер */
    static var rightIcon: String { get { get("rightIcon", "spark") } set { d.set(newValue, forKey: "rightIcon") } }
}
