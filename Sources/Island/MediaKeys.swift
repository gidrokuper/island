import AppKit
import ApplicationServices

/*
 Клавиши громкости (F10–F12 / тач-бар) перехватываем сами: громкость меняет остров,
 а системная плашка macOS не появляется. Нужен «Универсальный доступ» для острова.
 Без него клавиши работают как обычно, и показывается системная плашка.
*/
final class MediaKeys {
    enum Key { case up, down, mute }

    var handler: ((Key, NSEvent.ModifierFlags) -> Void)?
    fileprivate var tap: CFMachPort?
    private var waiting: Timer?

    var active: Bool { tap != nil }

    func start() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) {
            install()
        } else {
            /* ждём, пока пользователь выдаст доступ */
            waiting = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                if AXIsProcessTrusted() { t.invalidate(); self?.install() }
            }
        }
    }

    private func install() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << 14) /* NX_SYSDEFINED */
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: mediaKeyCallback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap = t
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }
}

private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let me = Unmanaged<MediaKeys>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
        return Unmanaged.passUnretained(event)
    }
    let code = (ns.data1 & 0xFFFF0000) >> 16
    let state = (ns.data1 & 0xFF00) >> 8
    let key: MediaKeys.Key
    switch code {
    case 0: key = .up        /* NX_KEYTYPE_SOUND_UP */
    case 1: key = .down      /* NX_KEYTYPE_SOUND_DOWN */
    case 7: key = .mute      /* NX_KEYTYPE_MUTE */
    default: return Unmanaged.passUnretained(event)
    }
    if state == 0xA {
        let flags = ns.modifierFlags
        DispatchQueue.main.async { me.handler?(key, flags) }
    }
    /* и нажатие, и отпускание глотаем — система плашку не покажет */
    return nil
}
