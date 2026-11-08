import AppKit
import Darwin
import IOKit.ps

struct Track: Equatable {
    var app: String
    var title: String
    var artist: String
    var playing: Bool
    var position: Double
    var duration: Double
    var fetched: Date
    var key: String
    var artURL: String
    var shuffle = false
    var repeatMode = 0      /* 0 — выкл, 1 — весь список, 2 — один трек */

    func now(_ date: Date) -> Double {
        let p = position + (playing ? date.timeIntervalSince(fetched) : 0)
        return duration > 0 ? min(p, duration) : p
    }
}

struct Battery: Equatable {
    var present = false
    var level = 100
    var charging = false
    var plugged = false
}

/* Сессия Claude Code, которая сейчас работает. */
struct Activity: Equatable, Identifiable {
    var id: String { session }
    var session: String
    var project: String
    var started: Date
    var bundle: String?
    var last: Date
    var action = L("Думаю…", "Thinking…")
}

struct Notice: Equatable, Identifiable {
    enum Kind { case done, attention, info }
    let id = UUID()
    var kind: Kind
    var source: String
    var title: String
    var body: String
    var bundle: String?
    /* чья иконка в уведомлении */
    var icon: String?
    /* фото отправителя (Telegram и др.) — вместо иконки приложения */
    var avatar: NSImage? = nil
    var at = Date()
}

let claudeBundle = "com.anthropic.claudefordesktop"

func appIcon(_ bundle: String?) -> NSImage? {
    guard let bundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
}

func clock(_ s: Double) -> String {
    let v = Int(s.isFinite ? max(0, s) : 0)
    return v >= 3600 ? String(format: "%d:%02d:%02d", v / 3600, v / 60 % 60, v % 60)
                     : String(format: "%d:%02d", v / 60, v % 60)
}

final class IslandModel: ObservableObject {
    enum Mode: Equatable { case idle, music, working, flash, device, focus, volume, notice, expanded }

    @Published private(set) var mode: Mode = .idle
    /* растёт ли остров при последней смене режима — от этого зависит пружина */
    private(set) var opening = true
    var onModeChange: (() -> Void)?

    @Published var expanded = false { didSet { recompute() } }
    @Published var hover = false
    @Published var track: Track? { didSet { recompute() } }
    /* запущен ли Claude (приложение или Claude Code в терминале) — без него искру не показываем */
    @Published var claudeRunning = false { didSet { if claudeRunning != oldValue { recompute() } } }
    @Published var art: NSImage?
    @Published var battery = Battery()
    @Published var flash = false { didSet { recompute() } }
    @Published var notch = CGSize(width: 190, height: 32)
    @Published var activities: [Activity] = [] { didSet { recompute() } }
    @Published var notice: Notice? { didSet { recompute() } }
    var noticeHover = false
    @Published var connected: OutputDevice? { didSet { recompute() } }
    let sound = SoundSystem()
    private var deviceWork: DispatchWorkItem?
    @Published var volumeHUD = false { didSet { recompute() } }
    /* плашка громкости показывает яркость экрана */
    @Published var hudBrightness = false
    /* раскрыт командой Island expand — не сворачивать, пока курсор не над островом */
    var pinned = Date.distantPast
    @Published var brightness: Float = Brightness.get()
    struct FocusEvent: Equatable { var mode: FocusMode; var on: Bool }
    @Published var focusEvent: FocusEvent? { didSet { recompute() } }
    let focus = FocusWatcher()
    let keys = MediaKeys()
    let system = SystemNotifications()
    private var lastHookNotice = Date.distantPast
    private var focusWork: DispatchWorkItem?
    private var volumeWork: DispatchWorkItem?

    private let music = MusicSource()
    private var artKey = ""
    private var flashWork: DispatchWorkItem?
    private var noticeWork: DispatchWorkItem?
    private var queue: [Notice] = []

    /* музыка играет и её показ включён в настройках */
    var musicOn: Bool { track?.playing == true && Prefs.showMusic }

    /* настройки поменялись в меню — перерисовать */
    func prefsChanged() {
        objectWillChange.send()
        recompute()
    }

    private func recompute() {
        let m: Mode
        if notice != nil { m = .notice }
        else if expanded { m = .expanded }
        else if volumeHUD { m = .volume }
        else if focusEvent != nil { m = .focus }
        else if connected != nil { m = .device }
        else if flash { m = .flash }
        else if !activities.isEmpty { m = .working }
        else if musicOn { m = .music }
        else { m = .idle }
        guard m != mode else { return }
        let a = bodySize(mode), b = bodySize(m)
        opening = b.width * b.height >= a.width * a.height
        mode = m
        onModeChange?()
    }

    var collapsedMode: Mode {
        if volumeHUD { return .volume }
        if focusEvent != nil { return .focus }
        if connected != nil { return .device }
        if flash { return .flash }
        if !activities.isEmpty { return .working }
        if musicOn { return .music }
        return .idle
    }

    /* обычный чат Claude: пока в окне есть «Остановить ответ» — показываем его как работу Claude */
    private let chatQueue = DispatchQueue(label: "island.claude-chat", qos: .utility)
    private var chatBusy = false
    static let chatSession = "claude-chat"

    func pollClaudeChat() {
        guard Prefs.claudeChat, !chatBusy,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == claudeBundle }) else {
            if activities.contains(where: { $0.session == Self.chatSession }) { activities.removeAll { $0.session == Self.chatSession } }
            return
        }
        chatBusy = true
        chatQueue.async { [weak self] in
            let on = ClaudeChat.answering()
            DispatchQueue.main.async {
                guard let self else { return }
                self.chatBusy = false
                /* кнопка «Остановить ответ» есть только у обычного чата: у Claude Code своя, её тут не видно */
                let has = self.activities.contains { $0.session == Self.chatSession }
                if on && !has {
                    var a = Activity(session: Self.chatSession, project: "", started: Date(), bundle: claudeBundle, last: Date())
                    a.action = L("Отвечает в чате", "Replying in chat")
                    self.activities.append(a)
                } else if !on && has {
                    self.activities.removeAll { $0.session == Self.chatSession }
                } else if on, let k = self.activities.firstIndex(where: { $0.session == Self.chatSession }) {
                    self.activities[k].last = Date()
                }
            }
        }
    }

    func refreshClaude() {
        let app = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == claudeBundle }
        claudeRunning = app || !activities.isEmpty || Self.processRunning("claude")
    }

    /* есть ли процесс с таким именем (Claude Code в терминале называется «claude») */
    static func processRunning(_ name: String) -> Bool {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(n) + 32)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var buf = [CChar](repeating: 0, count: 256)
        for p in pids.prefix(Int(max(0, got))) where p > 0 {
            if proc_name(p, &buf, UInt32(buf.count)) > 0, String(cString: buf) == name { return true }
        }
        return false
    }

    func bodySize(_ m: Mode) -> CGSize {
        let n = notch
        switch m {
        case .idle:
            /* искра Claude у выреза; Claude закрыт — только сам вырез */
            return claudeRunning ? CGSize(width: n.width + 2 * 34, height: n.height) : n
        case .music: return CGSize(width: n.width + 2 * 46, height: n.height)
        case .working:
            /* по ширине текста — компактно, как плашка громкости */
            let a = activities.last
            func w(_ s: String, _ wt: NSFont.Weight) -> CGFloat {
                (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: wt)]).width
            }
            /* играет музыка — остров держит размер плеера, текст обрезается */
            if musicOn { return CGSize(width: n.width + 2 * 46, height: n.height + 24) }
            var cw: CGFloat = 12 + 6 + w(a?.action ?? L("Думаю…", "Thinking…"), .medium) + 6 + 32 + 24
            cw += 12 + 6  /* значок Claude вместо названия проекта */
            if activities.count > 1 { cw += 22 }
            /* не уже, чем в покое: искра слева от выреза не должна заезжать под чёлку */
            return CGSize(width: min(max(cw, n.width + 2 * 34), n.width + 150), height: n.height + 24)
        case .flash: return CGSize(width: n.width + 2 * 64, height: n.height)
        case .device:
            if connected?.airpods == true { return CGSize(width: max(n.width + 2 * 18, 100), height: n.height + 54) }  /* только наушники под вырезом */
            return CGSize(width: n.width + 2 * 70, height: n.height)
        case .focus: return CGSize(width: n.width + 2 * 92, height: n.height)
        case .volume: return CGSize(width: max(n.width + 70, 290), height: n.height + 30)
        case .notice: return CGSize(width: max(440, n.width + 240), height: n.height + 70)
        case .expanded:
            let extra: CGFloat = activities.isEmpty ? 0 : 42
            return CGSize(width: max(560, n.width + 340), height: n.height + 160 + extra + (Brightness.available ? 30 : 0))
        }
    }

    static func notchSize(of s: NSScreen) -> CGSize {
        let h = s.safeAreaInsets.top
        if h > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return CGSize(width: s.frame.width - l.width - r.width, height: h)
        }
        return CGSize(width: 190, height: 32)
    }

    func start() {
        refreshBattery(initial: true)
        refreshClaude()
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.pollClaudeChat() }
        refreshMusic()
        sound.onConnect = { [weak self] d in self?.showDevice(d) }
        sound.onVolumeChange = { [weak self] in self?.hudBrightness = false; self?.showVolume() }
        focus.onChange = { [weak self] new, old in
            if let new { self?.showFocus(FocusEvent(mode: new, on: true)) }
            else if let old { self?.showFocus(FocusEvent(mode: old, on: false)) }
        }
        focus.start()
        keys.handler = { [weak self] k, f in self?.volumeKey(k, f) }
        keys.start()
        system.onNote = { [weak self] n in self?.systemNote(n) }
        system.start()
        sound.start()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refreshMusic() }
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshBattery(initial: false)
            self?.refreshClaude()
            self?.dropStale()
        }
        DistributedNotificationCenter.default().addObserver(forName: CLI.event, object: nil, queue: .main) { [weak self] n in
            let info = (n.userInfo as? [String: String]) ?? [:]
            self?.handle(info)
        }
    }

    // MARK: Claude Code

    static func project(from cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "" }
        if let r = cwd.range(of: "/.claude/worktrees/") {
            return URL(fileURLWithPath: String(cwd[..<r.lowerBound])).lastPathComponent
        }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    static func russian(_ message: String) -> String {
        guard Lang.russian else { return message }
        if message.lowercased().contains("waiting for your input") { return "Ждёт вашего ответа" }
        if let r = message.range(of: "permission to use ") {
            return "Просит разрешение: " + message[r.upperBound...]
        }
        if message.lowercased().contains("permission") { return "Просит разрешение" }
        return message
    }

    func handle(_ i: [String: String]) {
        let ev = i["event"] ?? ""
        let sid = i["session"] ?? ""
        let project = Self.project(from: i["cwd"])
        let bundle = (i["bundle"]?.isEmpty == false) ? i["bundle"] : nil
        switch ev {
        case "UserPromptSubmit":
            activities.removeAll { $0.session == sid }
            activities.append(Activity(session: sid, project: project, started: Date(), bundle: bundle, last: Date()))
        case "PreToolUse":
            let act = i["action"] ?? ""
            if let k = activities.firstIndex(where: { $0.session == sid }) {
                activities[k].last = Date()
                if !act.isEmpty { activities[k].action = act }
            } else {
                /* сессия шла ещё до запуска острова */
                var a = Activity(session: sid, project: project, started: Date(), bundle: bundle, last: Date())
                if !act.isEmpty { a.action = act }
                activities.append(a)
            }
        case "Stop":
            lastHookNotice = Date()
            let a = activities.first { $0.session == sid }
            activities.removeAll { $0.session == sid }
            var title = project.isEmpty ? L("Готово", "Done") : "\(project) — " + L("готово", "done")
            if let a, Date().timeIntervalSince(a.started) >= 5 { title += L(" за ", " in ") + clock(Date().timeIntervalSince(a.started)) }
            if Prefs.claudeNotices { show(Notice(kind: .done, source: "Claude Code", title: title,
                        body: i["summary"] ?? "", bundle: bundle ?? a?.bundle ?? claudeBundle, icon: claudeBundle)) }
        case "Notification":
            lastHookNotice = Date()
            let a = activities.first { $0.session == sid }
            if Prefs.claudeNotices { show(Notice(kind: .attention, source: "Claude Code",
                        title: project.isEmpty ? L("Claude ждёт вас", "Claude needs you") : "\(project) — " + L("нужны вы", "needs you"),
                        body: Self.russian(i["message"] ?? ""), bundle: bundle ?? a?.bundle ?? claudeBundle, icon: claudeBundle)) }
        case "SessionEnd":
            activities.removeAll { $0.session == sid }
        case "AXDump":
            ClaudeChat.dump()
        case "Bright":
            /* для проверки: шаг яркости из острова и плашка */
            setBrightness(Brightness.get() + (i["message"] == "down" ? -1 : 1) / 16)
            volumeKey(i["message"] == "down" ? .brightDown : .brightUp, [])
        case "Expand":
            pinned = Date().addingTimeInterval(6)
            expanded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.expanded = false }
        case "Like":
            saveTrack()
        case "SoundMenu":
            openSoundMenu()
        case "Demo":
            showDevice(sound.demoDevice(inCase: i["message"] == "case"))
        case "Notify":
            show(Notice(kind: .info, source: i["source"] ?? L("Остров", "Island"), title: i["title"] ?? "",
                        body: i["message"] ?? "", bundle: bundle, icon: bundle ?? Bundle.main.bundleIdentifier))
        default:
            break
        }
    }

    private func dropStale() {
        let old = activities.filter { Date().timeIntervalSince($0.last) > 3 * 3600 }
        if !old.isEmpty { activities.removeAll { a in old.contains { $0.session == a.session } } }
    }

    // MARK: Уведомления

    func show(_ n: Notice) {
        if notice == nil {
            notice = n
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            scheduleDismiss(after: n.kind == .attention ? max(9, Prefs.noticeSeconds) : Prefs.noticeSeconds)
        } else {
            queue.append(n)
        }
    }

    private func scheduleDismiss(after s: Double) {
        noticeWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.noticeHover { self.scheduleDismiss(after: 1.5) } else { self.dismissNotice() }
        }
        noticeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: w)
    }

    func dismissNotice() {
        noticeWork?.cancel()
        notice = nil
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.show(next) }
    }

    func openNotice() {
        if let b = notice?.bundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        }
        dismissNotice()
    }

    // MARK: Музыка и батарея

    /* треки, добавленные в медиатеку из острова (ключ трека) */
    @Published var saved: Set<String> = []

    /* «Добавить в медиатеку»: в Музыке — избранное, в Spotify — «Любимые треки» (его сочетание ⌥⇧B) */
    func saveTrack() {
        guard let t = track else { return }
        let on = !saved.contains(t.key)
        if music.save(t, on) { if on { saved.insert(t.key) } else { saved.remove(t.key) } }
    }

    func control(_ cmd: MusicSource.Command) {
        guard let t = track else { return }
        music.send(cmd, to: t.app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.refreshMusic() }
    }

    private func refreshMusic() {
        let t = music.current()
        if t != track { track = t }
        guard let t else {
            if art != nil { art = nil; artKey = "" }
            return
        }
        if t.key != artKey {
            artKey = t.key
            let key = t.key
            music.artwork(for: t) { [weak self] img in
                guard let self, self.artKey == key else { return }
                self.art = img
            }
        }
    }

    private func refreshBattery(initial: Bool) {
        let b = Self.readBattery()
        let wasPlugged = battery.plugged
        if b != battery { battery = b }
        if !initial && b.present && b.plugged && !wasPlugged { showFlash() }
    }

    /* уведомление любого приложения из Центра уведомлений */
    func systemNote(_ n: SystemNote) {
        if n.bundle == Bundle.main.bundleIdentifier { return }
        /* в режиме фокуса не мешаем */
        guard Prefs.appNotices else { return }
        /* беззвучные (заглушённые чаты) — не показываем, если не включено в настройках */
        if !n.hasSound && !Prefs.silentNotices { return }
        if Prefs.quietInFocus && focus.current != nil { return }
        /* у Claude Code уже есть своё уведомление из хука — без дублей */
        if n.bundle == claudeBundle && Date().timeIntervalSince(lastHookNotice) < 20 { return }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: n.bundle)
        let app = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? n.bundle
        let body = [n.subtitle, n.body].filter { !$0.isEmpty }.joined(separator: " — ")
        show(Notice(kind: .info, source: app, title: n.title.isEmpty ? app : n.title,
                    body: body, bundle: n.bundle, icon: n.bundle, avatar: n.image))
    }

    func showFocus(_ e: FocusEvent) {
        focusWork?.cancel()
        focusEvent = e
        let w = DispatchWorkItem { [weak self] in self?.focusEvent = nil }
        focusWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }

    /* клавиши громкости: шаг 1/16, с ⌥⇧ — мелкий шаг 1/64 */
    func setBrightness(_ v: Float) {
        Brightness.set(v)
        brightness = max(0, min(1, v))
    }

    func volumeKey(_ k: MediaKeys.Key, _ f: NSEvent.ModifierFlags) {
        let step: Float = f.contains(.option) && f.contains(.shift) ? 1 / 64 : 1 / 16
        if k == .brightUp || k == .brightDown {
            /* Яркость по клавише macOS меняет сама (даже когда событие перехвачено — системная плашка
               при этом скрыта). Если менять ещё и из острова, два значения спорят и экран мерцает.
               Поэтому остров только показывает то, что выставила система. */
            hudBrightness = true
            showVolume()
            for d in [0.05, 0.12, 0.25, 0.45, 0.7] {
                DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in self?.brightness = Brightness.get() }
            }
            return
        }
        hudBrightness = false
        let v = sound.muted ? 0 : sound.volume
        switch k {
        case .up: sound.setVolume(((v / step).rounded() + 1) * step)
        case .down: sound.setVolume(max(0, ((v / step).rounded() - 1) * step))
        case .mute: sound.setMuted(!sound.muted)
        default: break
        }
        showVolume()
    }

    func showVolume() {
        guard !expanded else { return }
        volumeWork?.cancel()
        if !volumeHUD { volumeHUD = true }
        let w = DispatchWorkItem { [weak self] in self?.volumeHUD = false }
        volumeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: w)
    }

    /* меню «Звук» с режимами наушников; плашку подключения при этом убираем */
    func openSoundMenu() {
        deviceWork?.cancel()
        connected = nil
        expanded = false
        DispatchQueue.main.async { SoundMenu.open() }
    }

    func showDevice(_ d: OutputDevice) {
        deviceWork?.cancel()
        connected = d
        let w = DispatchWorkItem { [weak self] in self?.connected = nil }
        deviceWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (d.airpods ? 6 : 4), execute: w)
    }

    private func showFlash() {
        flashWork?.cancel()
        flash = true
        let w = DispatchWorkItem { [weak self] in self?.flash = false }
        flashWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }

    static func readBattery() -> Battery {
        var b = Battery()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return b }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            b.present = true
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 100
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            b.level = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            b.charging = d[kIOPSIsChargingKey] as? Bool ?? false
            b.plugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        }
        return b
    }
}

/* Что играет: Музыка и Spotify через AppleScript. Приложение не запускаем, если оно закрыто. */
final class MusicSource {
    enum Command { case toggle, next, previous, shuffle, repeatMode }

    private var cache: [String: NSAppleScript] = [:]
    private let sep = "|~|"

    private static let apps: [(name: String, bundle: String)] = [
        ("Music", "com.apple.Music"),
        ("Spotify", "com.spotify.client"),
    ]

    private func run(_ src: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let s = cache[src] {
            script = s
        } else {
            guard let s = NSAppleScript(source: src) else { return nil }
            var e: NSDictionary?
            s.compileAndReturnError(&e)
            cache[src] = s
            script = s
        }
        var err: NSDictionary?
        let r = script.executeAndReturnError(&err)
        return err == nil ? r : nil
    }

    private func isRunning(_ bundle: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundle }
    }

    private func num(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
    }

    func current() -> Track? {
        var found: [Track] = []
        let src = Prefs.musicSource
        for a in Self.apps where isRunning(a.bundle) && (src == "all" || (src == "spotify") == (a.name == "Spotify")) {
            if let t = read(a.name) { found.append(t) }
        }
        return found.first { $0.playing } ?? found.first
    }

    private func read(_ app: String) -> Track? {
        let src: String
        if app == "Music" {
            src = """
            tell application "Music"
              if player state is stopped then return ""
              set t to current track
              return (name of t) & "\(sep)" & (artist of t) & "\(sep)" & (player state as string) & "\(sep)" & (player position as string) & "\(sep)" & (duration of t as string) & "\(sep)" & (persistent ID of t) & "\(sep)" & "" & "\(sep)" & (shuffle enabled as string) & "\(sep)" & (song repeat as string)
            end tell
            """
        } else {
            src = """
            tell application "Spotify"
              if player state is stopped then return ""
              set t to current track
              return (name of t) & "\(sep)" & (artist of t) & "\(sep)" & (player state as string) & "\(sep)" & (player position as string) & "\(sep)" & ((duration of t) / 1000 as string) & "\(sep)" & (id of t) & "\(sep)" & (artwork url of t) & "\(sep)" & (shuffling as string) & "\(sep)" & (repeating as string)
            end tell
            """
        }
        guard let s = run(src)?.stringValue, !s.isEmpty else { return nil }
        let p = s.components(separatedBy: sep)
        guard p.count >= 7 else { return nil }
        return Track(app: app, title: p[0], artist: p[1], playing: p[2] == "playing",
                     position: num(p[3]), duration: num(p[4]), fetched: Date(),
                     key: app + ":" + p[5], artURL: p[6],
                     shuffle: p.count > 7 && p[7] == "true",
                     repeatMode: p.count > 8 ? (p[8] == "true" || p[8] == "all" ? 1 : p[8] == "one" ? 2 : 0) : 0)
    }

    /* on: добавить или убрать. Сочетание Spotify переключает, поэтому для него on не важен */
    func save(_ t: Track, _ on: Bool) -> Bool {
        if t.app == "Music" {
            return run("tell application \"Music\" to set favorited of current track to \(on)") != nil
                || run("tell application \"Music\" to set loved of current track to \(on)") != nil
        }
        /* у Spotify нет команды AppleScript — шлём его сочетание «Сохранить в Любимые треки» прямо приложению */
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first else { return false }
        let src = CGEventSource(stateID: .hidSystemState)
        let b: CGKeyCode = 11
        let flags: CGEventFlags = [.maskAlternate, .maskShift]
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: b, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: b, keyDown: false) else { return false }
        down.flags = flags; up.flags = flags
        down.postToPid(app.processIdentifier)
        up.postToPid(app.processIdentifier)
        return true
    }

    func send(_ cmd: Command, to app: String) {
        let verb: String
        let music = app == "Music"
        switch cmd {
        case .toggle: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .shuffle: verb = music ? "set shuffle enabled to not shuffle enabled" : "set shuffling to not shuffling"
        case .repeatMode:
            verb = music
                ? "if song repeat is off then\nset song repeat to all\nelse if song repeat is all then\nset song repeat to one\nelse\nset song repeat to off\nend if"
                : "set repeating to not repeating"
        }
        if verb.contains("\n") {
            _ = run("tell application \"\(app)\"\n\(verb)\nend tell")
            return
        }
        _ = run("tell application \"\(app)\" to \(verb)")
    }

    func artwork(for t: Track, done: @escaping (NSImage?) -> Void) {
        if t.app == "Music" {
            let d = run("tell application \"Music\" to get raw data of artwork 1 of current track")?.data
            done(d.flatMap { NSImage(data: $0) })
        } else if let url = URL(string: t.artURL), !t.artURL.isEmpty {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                let img = data.flatMap { NSImage(data: $0) }
                DispatchQueue.main.async { done(img) }
            }.resume()
        } else {
            done(nil)
        }
    }
}
