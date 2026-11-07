import AppKit
import SQLite3

struct SystemNote {
    var bundle: String
    var title: String
    var subtitle: String
    var body: String
    /* картинка из уведомления: у Telegram это аватарка отправителя */
    var image: NSImage? = nil
    /* со звуком ли пришло: у беззвучных (например, заглушённый чат) в записи нет ключа soun */
    var hasSound = true
}

/*
 Уведомления всех приложений: читаем базу Центра уведомлений
 ~/Library/Group Containers/group.com.apple.usernoted/db2/db (только чтение) и шлём новые записи в остров.
 Нужен «Полный доступ к диску» (тот же, что для режимов фокуса).
*/
final class SystemNotifications {
    var onNote: ((SystemNote) -> Void)?
    private(set) var readable = false
    /*
     Новые записи ищем по времени доставки, а не по rec_id: после очистки Центра уведомлений
     SQLite снова выдаёт номера с меньших значений, и сравнение по номеру теряло уведомления.
    */
    private var lastDate: Double = -1
    private var seen: [Data] = []
    /* первый проход только запоминает, что уже лежит в базе, — старое не показываем */
    private var primed = false
    private let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db").path
    private let when = "COALESCE(r.delivered_date, r.request_date, 0)"

    func start() {
        lastDate = maxDate() ?? -1
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func open() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            readable = false
            return nil
        }
        sqlite3_busy_timeout(db, 200)
        return db
    }

    private func maxDate() -> Double? {
        guard let db = open() else { return nil }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(\(when)), 0) FROM record r", -1, &st, nil) == SQLITE_OK else {
            readable = false
            return nil
        }
        defer { sqlite3_finalize(st) }
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        readable = true
        return sqlite3_column_double(st, 0)
    }

    private func tick() {
        if lastDate < 0 { lastDate = maxDate() ?? -1; return }
        guard let db = open() else { return }
        defer { sqlite3_close(db) }
        let sql = "SELECT \(when), a.identifier, r.data, r.uuid FROM record r JOIN app a ON a.app_id = r.app_id WHERE \(when) >= ? ORDER BY \(when)"
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { readable = false; return }
        defer { sqlite3_finalize(st) }
        readable = true
        sqlite3_bind_double(st, 1, lastDate)
        var notes: [SystemNote] = []
        while sqlite3_step(st) == SQLITE_ROW {
            let date = sqlite3_column_double(st, 0)
            let uuid = sqlite3_column_blob(st, 3).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(st, 3))) } ?? Data()
            /* запись с тем же временем уже показана — пропускаем */
            if seen.contains(uuid) { continue }
            seen.append(uuid)
            if seen.count > 200 { seen.removeFirst(seen.count - 200) }
            lastDate = max(lastDate, date)
            let bundle = sqlite3_column_text(st, 1).map { String(cString: $0) } ?? ""
            guard let bytes = sqlite3_column_blob(st, 2) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(st, 2)))
            if let n = Self.parse(data, bundle: bundle) { notes.append(n) }
        }
        /* если пришла пачка (например, после сна) — показываем только последние три */
        if !primed { primed = true; return }
        for n in notes.suffix(3) { onNote?(n) }
    }

    static func parse(_ data: Data, bundle: String) -> SystemNote? {
        guard let p = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let req = p["req"] as? [String: Any] else { return nil }
        func text(_ k: String) -> String {
            if let s = req[k] as? String { return s }
            return (req[k] as? [Any])?.compactMap { $0 as? String }.first ?? ""
        }
        /* вложение читаем сразу: приложение может убрать уведомление вместе с файлом */
        let image = (req["atta"] as? [[String: Any]])?
            .first { ($0["uti"] as? String).map { $0.hasPrefix("public.") && $0 != "public.data" } ?? false }
            .flatMap { $0["pat"] as? String }
            .flatMap { NSImage(contentsOfFile: $0) }
        let n = SystemNote(bundle: (p["app"] as? String) ?? bundle,
                           title: text("titl"), subtitle: text("subt"), body: text("body"), image: image,
                           hasSound: req["soun"] != nil)
        return n.title.isEmpty && n.body.isEmpty ? nil : n
    }
}
