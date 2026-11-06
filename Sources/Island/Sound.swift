import AudioToolbox
import CoreAudio
import Foundation

struct OutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    var name: String
    var transport: UInt32
    var symbol: String
    var battery: Int?
    /* AirPods: заряд левого, правого и кейса (кейс виден, когда наушники в нём) */
    var left: Int? = nil
    var right: Int? = nil
    var caseLevel: Int? = nil

    var airpods: Bool { symbol.hasPrefix("airpods") }
    var inCase: Bool { caseLevel != nil }

    var bluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
    var builtIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
}

/* Звук: громкость, выходы, подключение наушников. Только публичный CoreAudio. */
final class SoundSystem: ObservableObject {
    @Published var outputs: [OutputDevice] = []
    @Published var current: AudioDeviceID = 0
    @Published var volume: Float = 0
    @Published var muted = false

    var onConnect: ((OutputDevice) -> Void)?
    /* громкость поменялась снаружи: клавиши, меню, другое приложение */
    var onVolumeChange: (() -> Void)?

    private let sys = AudioObjectID(kAudioObjectSystemObject)
    private var known: Set<AudioDeviceID> = []
    private var watched: Set<AudioDeviceID> = []
    private var bt: [String: BTInfo] = [:]
    struct BTInfo { var symbol: String; var battery: Int?; var left: Int?; var right: Int?; var caseLevel: Int? }
    private var btBusy = false

    func start() {
        reload(initial: true)
        listen(sys, kAudioHardwarePropertyDevices) { [weak self] in self?.reload(initial: false) }
        listen(sys, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.reload(initial: false) }
        refreshBluetooth(nil)
        Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            guard let self, self.outputs.contains(where: { $0.bluetooth }) else { return }
            self.refreshBluetooth(nil)
        }
    }

    // MARK: Управление

    func select(_ id: AudioDeviceID) {
        var v = id
        var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(sys, &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &v)
    }

    func setVolume(_ v: Float) {
        var x = max(0, min(1, v))
        volume = x
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(current, &a, 0, nil, 4, &x)
        if muted && x > 0 { setMuted(false) }
    }

    func setMuted(_ m: Bool) {
        var x: UInt32 = m ? 1 : 0
        var a = addr(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(current, &a, 0, nil, 4, &x)
        muted = m
    }

    // MARK: Чтение

    private func addr(_ sel: AudioObjectPropertySelector,
                      _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func listen(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ f: @escaping () -> Void) {
        var a = addr(sel, scope)
        AudioObjectAddPropertyListenerBlock(obj, &a, DispatchQueue.main) { _, _ in f() }
    }

    private func deviceIDs() -> [AudioDeviceID] {
        var a = addr(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func hasOutput(_ id: AudioDeviceID) -> Bool {
        var a = addr(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr && size > 0
    }

    private func name(_ id: AudioDeviceID) -> String {
        var a = addr(kAudioObjectPropertyName)
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &s) == noErr, let s else { return "" }
        return s.takeRetainedValue() as String
    }

    private func u32(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32 {
        var a = addr(sel, scope)
        var v: UInt32 = 0
        var size = UInt32(4)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v)
        return v
    }

    private func defaultOutput() -> AudioDeviceID {
        var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &id)
        return id
    }

    private func readVolume() {
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        var v = Float32(0)
        var size = UInt32(4)
        if AudioObjectGetPropertyData(current, &a, 0, nil, &size, &v) == noErr, abs(v - volume) > 0.001 { volume = v }
        let m = u32(current, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput) == 1
        if m != muted { muted = m }
    }

    private func symbol(for transport: UInt32, name: String) -> String {
        if let s = bt[name]?.symbol { return s }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        default: return "hifispeaker"
        }
    }

    private func reload(initial: Bool) {
        let ids = deviceIDs().filter { id in
            let t = u32(id, kAudioDevicePropertyTransportType)
            return hasOutput(id) && t != kAudioDeviceTransportTypeAggregate && t != kAudioDeviceTransportTypeVirtual
        }
        let list: [OutputDevice] = ids.map { id in
            let t = u32(id, kAudioDevicePropertyTransportType)
            let n = name(id)
            return OutputDevice(id: id, name: n, transport: t, symbol: symbol(for: t, name: n), battery: bt[n]?.battery)
        }
        .sorted { ($0.builtIn ? 0 : 1, $0.name) < ($1.builtIn ? 0 : 1, $1.name) }
        if list != outputs { outputs = list }
        let cur = defaultOutput()
        if cur != current { current = cur }
        for id in ids where !watched.contains(id) {
            watched.insert(id)
            listen(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput) { [weak self] in
                guard let self, self.current == id else { return }
                self.readVolume()
                self.onVolumeChange?()
            }
            listen(id, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput) { [weak self] in
                guard let self, self.current == id else { return }
                self.readVolume()
                self.onVolumeChange?()
            }
        }
        readVolume()

        let fresh = list.filter { $0.bluetooth && !known.contains($0.id) }
        known = Set(ids)
        if !initial && !fresh.isEmpty {
            /* сначала узнаём модель и заряд, потом показываем */
            refreshBluetooth { [weak self] in
                guard let self else { return }
                for f in fresh { if let d = self.outputs.first(where: { $0.id == f.id }) { self.onConnect?(d) } }
            }
        }
    }

    // MARK: Bluetooth: модель наушников и заряд

    static func airpodsSymbol(product: String, minor: String) -> String {
        switch product.lowercased() {
        case "0x200e", "0x2014", "0x2024", "0x2027": return "airpods.pro"
        case "0x200a", "0x201f": return "airpods.max"
        case "0x2002", "0x200f": return "airpods"
        case "0x2013", "0x2019", "0x201b", "0x2025", "0x2026": return "airpods.gen3"
        default: return minor == "Speaker" ? "hifispeaker" : "headphones"
        }
    }

    func refreshBluetooth(_ done: (() -> Void)?) {
        guard !btBusy else { done?(); return }
        btBusy = true
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            var info: [String: BTInfo] = [:]
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                for blk in root?["SPBluetoothDataType"] as? [[String: Any]] ?? [] {
                    for dev in blk["device_connected"] as? [[String: Any]] ?? [] {
                        for (name, v) in dev {
                            guard let v = v as? [String: Any] else { continue }
                            func pct(_ k: String) -> Int? {
                                (v[k] as? String).flatMap { Int($0.filter(\.isNumber)) }
                            }
                            let lr = [pct("device_batteryLevelLeft"), pct("device_batteryLevelRight")].compactMap { $0 }
                            let level = lr.min() ?? pct("device_batteryLevelMain") ?? pct("device_batteryLevel")
                            info[name] = BTInfo(symbol: Self.airpodsSymbol(product: v["device_productID"] as? String ?? "",
                                                                           minor: v["device_minorType"] as? String ?? ""),
                                                battery: level, left: pct("device_batteryLevelLeft"),
                                                right: pct("device_batteryLevelRight"), caseLevel: pct("device_batteryLevelCase"))
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                self.btBusy = false
                self.bt = info
                self.outputs = self.outputs.map { d in
                    var d = d
                    if let i = info[d.name] {
                        d.symbol = i.symbol; d.battery = i.battery
                        d.left = i.left; d.right = i.right; d.caseLevel = i.caseLevel
                    }
                    return d
                }
                done?()
            }
        }
    }

    /* для проверки и скриншотов: подключённые наушники или выдуманные AirPods Pro */
    func demoDevice(inCase: Bool) -> OutputDevice {
        var d = outputs.first { $0.airpods } ?? OutputDevice(id: 0, name: "AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth,
                                                             symbol: "airpods.pro", battery: 82, left: 82, right: 85)
        if d.left == nil { d.left = 82; d.right = 85 }
        d.caseLevel = inCase ? (d.caseLevel ?? 64) : nil
        return d
    }
}
