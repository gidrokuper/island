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

    static func set(_ v: Float) {
        _ = setFn?(display, max(0, min(1, v)))
    }
}
