import AppKit
import ServiceManagement
import SwiftUI

if CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("-") {
    CLI.run(Array(CommandLine.arguments.dropFirst()))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = IslandModel()
    var panel: IslandPanel!
    var pending: DispatchWorkItem?
    var poll: Timer?

    /* остров всегда на экране: не даём macOS усыплять его (App Nap), иначе анимации замирают */
    var awake: NSObjectProtocol?

    func applicationDidFinishLaunching(_ note: Notification) {
        awake = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Остров постоянно на экране и анимирует искру, музыку и уведомления")
        /* второй экземпляр не нужен */
        let me = Bundle.main.bundleIdentifier ?? ""
        if NSRunningApplication.runningApplications(withBundleIdentifier: me).count > 1 { NSApp.terminate(nil) }

        panel = IslandPanel(model: model, menu: { [weak self] in self?.makeMenu() ?? NSMenu() })
        place()
        panel.orderFrontRegardless()

        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.trackMouse()
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.model.expanded else { return }
            if !self.expandedRect().contains(NSEvent.mouseLocation) { self.setExpanded(false) }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.place() }

        model.onModeChange = { [weak self] in self?.modeChanged() }
        model.start()
        if ProcessInfo.processInfo.environment["ISLAND_DEBUG"] != nil {
            FileHandle.standardError.write("frame=\(panel.frame) visible=\(panel.isVisible) notch=\(model.notch)\n".data(using: .utf8)!)
        }
    }

    var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func place() {
        let s = screen
        model.notch = IslandModel.notchSize(of: s)
        let w: CGFloat = 820, h: CGFloat = 400
        panel.setFrame(NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - h, width: w, height: h), display: true)
    }

    func rect(_ mode: IslandModel.Mode, pad: CGFloat) -> NSRect {
        let f = screen.frame
        let size = model.bodySize(mode)
        let flare: CGFloat = (mode == .expanded || mode == .notice) ? 14 : 7
        let w = size.width + flare * 2
        return NSRect(x: f.midX - w / 2, y: f.maxY - size.height, width: w, height: size.height).insetBy(dx: -pad, dy: -pad)
    }

    func expandedRect() -> NSRect { rect(.expanded, pad: 10) }

    var interactive: Bool {
        model.mode == .expanded || model.mode == .notice || (model.mode == .device && model.connected?.airpods == true)
    }

    func modeChanged() {
        if interactive {
            if poll == nil {
                /* курсор над нашим окном — глобальный монитор молчит, опрашиваем сами */
                poll = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.trackMouse() }
            }
        } else {
            poll?.invalidate()
            poll = nil
            panel.ignoresMouseEvents = true
        }
        trackMouse()
    }

    func trackMouse() {
        let p = NSEvent.mouseLocation
        switch model.mode {
        case .notice:
            let inside = rect(.notice, pad: 4).contains(p)
            panel.ignoresMouseEvents = !inside
            model.noticeHover = inside
            if model.hover { model.hover = false }
        case .device where model.connected?.airpods == true:
            panel.ignoresMouseEvents = !rect(.device, pad: 4).contains(p)
        case .expanded:
            panel.ignoresMouseEvents = false
            if expandedRect().contains(p) { cancel() } else { schedule(false, after: 0.16) }
        default:
            let inside = rect(model.collapsedMode, pad: 6).contains(p)
            if model.hover != inside { model.hover = inside }
            if inside { schedule(true, after: 0.12) } else { cancel() }
        }
    }

    func cancel() { pending?.cancel(); pending = nil }

    func schedule(_ value: Bool, after: Double) {
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            self?.setExpanded(value)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: work)
    }

    func setExpanded(_ value: Bool) {
        cancel()
        guard model.expanded != value else { return }
        if value { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        model.hover = false
        model.expanded = value
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let login = ClosureItem(L("Запускать при входе", "Open at Login")) {
            let svc = SMAppService.mainApp
            if svc.status == .enabled { try? svc.unregister() } else { try? svc.register() }
        }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(ClosureItem(L("Проверить уведомление", "Test Notification")) { [weak self] in
            self?.setExpanded(false)
            self?.model.show(Notice(kind: .info, source: L("Остров", "Island"), title: L("Проверка уведомления", "Test notification"),
                                    body: L("Так будут выглядеть сообщения от Claude Code.", "This is how Claude Code messages will look."), bundle: claudeBundle, icon: claudeBundle))
        })
        if !model.focus.readable || !model.system.readable {
            menu.addItem(ClosureItem(L("Показывать фокус и уведомления…", "Show Focus and Notifications…")) { FocusWatcher.openPrivacySettings() })
        }
        menu.addItem(.separator())
        let m = model
        func changed() { m.prefsChanged() }
        func radio<T: Equatable>(_ title: String, _ items: [(String, T)], _ cur: T, _ set: @escaping (T) -> Void) -> NSMenuItem {
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (name, v) in items {
                let it = ClosureItem(name) { set(v); changed() }
                it.state = v == cur ? .on : .off
                sub.addItem(it)
            }
            root.submenu = sub
            return root
        }
        func toggle(_ title: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> ClosureItem {
            let it = ClosureItem(title) { set(!on); changed() }
            it.state = on ? .on : .off
            return it
        }

        menu.addItem(radio(L("Прозрачность", "Transparency"),
                           [(L("Выключена", "Off"), 1.0), (L("Лёгкая", "Light"), 0.88),
                            (L("Средняя", "Medium"), 0.78), (L("Сильная", "Strong"), 0.62)],
                           Prefs.opacity) { Prefs.opacity = $0 })

        let notes = NSMenuItem(title: L("Уведомления", "Notifications"), action: nil, keyEquivalent: "")
        let nm = NSMenu()
        nm.addItem(toggle(L("Уведомления приложений", "App notifications"), Prefs.appNotices) { Prefs.appNotices = $0 })
        nm.addItem(toggle(L("Беззвучные уведомления", "Silent notifications"), Prefs.silentNotices) { Prefs.silentNotices = $0 })
        nm.addItem(toggle(L("Уведомления Claude Code", "Claude Code notifications"), Prefs.claudeNotices) { Prefs.claudeNotices = $0 })
        nm.addItem(toggle(L("Не показывать в режиме фокуса", "Silence during Focus"), Prefs.quietInFocus) { Prefs.quietInFocus = $0 })
        nm.addItem(.separator())
        nm.addItem(radio(L("Время на экране", "Time on screen"),
                         [(L("4 секунды", "4 seconds"), 4.0), (L("6 секунд", "6 seconds"), 6.0), (L("10 секунд", "10 seconds"), 10.0)],
                         Prefs.noticeSeconds) { Prefs.noticeSeconds = $0 })
        notes.submenu = nm
        menu.addItem(notes)

        let player = NSMenuItem(title: L("Плеер", "Player"), action: nil, keyEquivalent: "")
        let pm = NSMenu()
        pm.addItem(toggle(L("Показывать музыку у выреза", "Show music at the notch"), Prefs.showMusic) { Prefs.showMusic = $0 })
        pm.addItem(radio(L("Источник", "Source"),
                         [(L("Музыка и Spotify", "Music and Spotify"), "all"), ("Spotify", "spotify"), (L("Музыка", "Music"), "music")],
                         Prefs.musicSource) { Prefs.musicSource = $0 })
        pm.addItem(radio(L("Справа от выреза", "Right of the notch"),
                         [(L("Искра Claude", "Claude spark"), "spark"), (L("Эквалайзер", "Equalizer"), "bars")],
                         Prefs.rightIcon) { Prefs.rightIcon = $0 })
        player.submenu = pm
        menu.addItem(player)

        menu.addItem(radio(L("Язык", "Language"), [("Русский", "ru"), ("English", "en")],
                           Lang.russian ? "ru" : "en") { UserDefaults.standard.set($0, forKey: "lang") })
        menu.addItem(.separator())
        menu.addItem(ClosureItem(L("Выйти", "Quit")) { NSApp.terminate(nil) })
        return menu
    }
}

final class ClosureItem: NSMenuItem {
    let handler: () -> Void
    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc func fire() { handler() }
}

final class IslandPanel: NSPanel {
    init(model: IslandModel, menu: @escaping () -> NSMenu) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = HostView(rootView: IslandView(m: model))
        host.sizingOptions = []
        host.menuProvider = menu
        contentView = host
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HostView<V: View>: NSHostingView<V> {
    var menuProvider: (() -> NSMenu)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func rightMouseDown(with event: NSEvent) {
        if let m = menuProvider?() { NSMenu.popUpContextMenu(m, with: event, for: self) }
    }
}
