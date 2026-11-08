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
     Плавный переход к значению, как у самой macOS: за 0,25 с, с мягким ускорением и замедлением,
     в «глазной» шкале (корень из яркости) — внизу шкалы шаги мельче. Текущее значение ведём сами,
     а не читаем с экрана каждый кадр (иначе округление экрана давало дрожание на низкой яркости).
     Новое нажатие во время перехода начинает новый переход с текущей точки.
    */
    private static var rampFrom: Float = 0
    private static var rampTo: Float = 0
    private static var rampNow: Float = -1
    private static var rampStart = Date()
    private static var rampTimer: Timer?
    private static let rampTime: Double = 0.25

    static func animate(to v: Float) {
        let target = max(0, min(1, v))
        rampFrom = rampTimer != nil && rampNow >= 0 ? rampNow : get()
        rampTo = target
        rampStart = Date()
        guard rampTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
            let p = min(1, Date().timeIntervalSince(rampStart) / rampTime)
            let e = Float(p * p * (3 - 2 * p))  /* smoothstep */
            let a = rampFrom.squareRoot(), b = rampTo.squareRoot()
            let x = a + (b - a) * e
            rampNow = x * x
            set(rampNow)
            if p >= 1 {
                timer.invalidate()
                rampTimer = nil
                rampNow = -1
            }
        }
        RunLoop.main.add(t, forMode: .common)
        rampTimer = t
    }

    static func set(_ v: Float) {
        let x = max(0, min(1, v))
        _ = setFn?(display, x)
    }
}
