import Foundation
import SQLite3

struct SystemNote {
    var bundle: String
    var title: String
    var subtitle: String
    var body: String
}

/*
 Уведомления всех приложений: читаем базу Центра уведомлений
 ~/Library/Group Containers/group.com.apple.usernoted/db2/db (только чтение) и шлём новые записи в остров.
 Нужен «Полный доступ к диску» (тот же, что для режимов фокуса).
*/
final class SystemNotifications {
    var onNote: ((SystemNote) -> Void)?
    private(set) var readable = false
    private var lastId: Int64 = -1
    private let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db").path

    func start() {
        lastId = maxId() ?? -1
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

    private func maxId() -> Int64? {
        guard let db = open() else { return nil }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(rec_id), 0) FROM record", -1, &st, nil) == SQLITE_OK else {
            readable = false
            return nil
        }
        defer { sqlite3_finalize(st) }
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        readable = true
        return sqlite3_column_int64(st, 0)
    }

    private func tick() {
        if lastId < 0 { lastId = maxId() ?? -1; return }
        guard let db = open() else { return }
        defer { sqlite3_close(db) }
        let sql = "SELECT r.rec_id, a.identifier, r.data FROM record r JOIN app a ON a.app_id = r.app_id WHERE r.rec_id > ? ORDER BY r.rec_id"
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { readable = false; return }
        defer { sqlite3_finalize(st) }
        readable = true
        sqlite3_bind_int64(st, 1, lastId)
        var notes: [SystemNote] = []
        while sqlite3_step(st) == SQLITE_ROW {
            lastId = max(lastId, sqlite3_column_int64(st, 0))
            let bundle = sqlite3_column_text(st, 1).map { String(cString: $0) } ?? ""
            guard let bytes = sqlite3_column_blob(st, 2) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(st, 2)))
            if let n = Self.parse(data, bundle: bundle) { notes.append(n) }
        }
        /* если пришла пачка (например, после сна) — показываем только последние три */
        for n in notes.suffix(3) { onNote?(n) }
    }

    static func parse(_ data: Data, bundle: String) -> SystemNote? {
        guard let p = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let req = p["req"] as? [String: Any] else { return nil }
        func text(_ k: String) -> String {
            if let s = req[k] as? String { return s }
            return (req[k] as? [Any])?.compactMap { $0 as? String }.first ?? ""
        }
        let n = SystemNote(bundle: (p["app"] as? String) ?? bundle,
                           title: text("titl"), subtitle: text("subt"), body: text("body"))
        return n.title.isEmpty && n.body.isEmpty ? nil : n
    }
}
