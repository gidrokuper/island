import CoreGraphics
import Foundation

/* Яркость встроенного экрана через DisplayServices (системная библиотека macOS, открытого API нет). */
enum Brightness {
    private typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (UInt32, Float) -> Int32
    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn: Get? = lib.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    private static let setFn: Set? = lib.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }

    static var display: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static var available: Bool { getFn != nil && setFn != nil }

    static func get() -> Float {
        var b: Float = 0
        guard let getFn, getFn(display, &b) == 0 else { return 0 }
        return b
    }

    /*
     Плавный переход к значению, как у самой macOS: ~0,15 с мелкими шагами вместо одного рывка
     (рывки на каждое нажатие выглядели как мерцание). Новое нажатие просто меняет цель.
    */
    private static var rampTarget: Float = 0
    private static var rampTimer: Timer?

    static func animate(to v: Float) {
        rampTarget = max(0, min(1, v))
        guard rampTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
            let cur = get()
            let diff = rampTarget - cur
            if abs(diff) < 0.004 {
                set(rampTarget)
                timer.invalidate()
                rampTimer = nil
                return
            }
            /* за кадр проходим треть оставшегося, но не меньше 0,004 — мягко и быстро */
            let step = diff > 0 ? max(diff / 3, 0.004) : min(diff / 3, -0.004)
            set(cur + step)
        }
        RunLoop.main.add(t, forMode: .common)
        rampTimer = t
    }

    static func set(_ v: Float) {
        let x = max(0, min(1, v))
        _ = setFn?(display, x)
    }
}
