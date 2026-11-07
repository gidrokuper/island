import SwiftUI

let accent = Color(red: 1.0, green: 0.48, blue: 0.13)
let spotifyGreen = Color(red: 0.12, green: 0.84, blue: 0.38)

/* Пружины: раскрытие — живое, с лёгким перелётом; сворачивание — быстрое и без отскока. */
enum Motion {
    static let open = Animation.spring(response: 0.52, dampingFraction: 0.72, blendDuration: 0.1)
    static let close = Animation.spring(response: 0.4, dampingFraction: 0.9, blendDuration: 0.1)
    static let hover = Animation.spring(response: 0.3, dampingFraction: 0.62)
    static let contentIn = Animation.spring(response: 0.42, dampingFraction: 0.82).delay(0.09)
    static let contentOut = Animation.easeIn(duration: 0.11)
}

/* Форма выреза: сверху «уши», которые плавно вливаются в рамку экрана, снизу скругления. */
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let b = min(bottom, r.height / 2, (r.width - 2 * top) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + b, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - b), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/* Появление содержимого: из размытия, чуть меньше и прозрачнее — как у системных островов. */
struct BlurFade: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: blur).opacity(opacity).scaleEffect(scale, anchor: .top)
    }
}

extension AnyTransition {
    static var island: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurFade(blur: 12, opacity: 0, scale: 0.82),
                                 identity: BlurFade(blur: 0, opacity: 1, scale: 1)).animation(Motion.contentIn),
            removal: .modifier(active: BlurFade(blur: 8, opacity: 0, scale: 0.96),
                               identity: BlurFade(blur: 0, opacity: 1, scale: 1)).animation(Motion.contentOut)
        )
    }
}

struct IslandView: View {
    @ObservedObject var m: IslandModel
    @Namespace private var ns

    var body: some View {
        let mode = m.mode
        let big = mode == .expanded || mode == .notice
        var s = m.bodySize(mode)
        if m.hover && !big { s.width += 14; s.height += 3 }
        /* AirPods: вырез не раскрываем, наушники висят под ним на прозрачном фоне */
        let floating = mode == .device && m.connected?.airpods == true
        let shape = floating ? m.notch : s
        let tr: CGFloat = big ? 14 : 7
        let br: CGFloat = big ? 34 : (mode == .volume || mode == .working ? 18 : 11)
        /* полупрозрачный фон; крупные панели чуть плотнее, чтобы текст читался */
        let fill = Color.black.opacity(big ? min(1, Prefs.opacity + 0.08) : Prefs.opacity)

        return ZStack(alignment: .top) {
            NotchShape(top: tr, bottom: br)
                .fill(fill)
                .frame(width: shape.width + tr * 2, height: shape.height)
                .shadow(color: .black.opacity(big ? 0.55 : 0), radius: big ? 24 : 0, y: big ? 12 : 0)

            if floating {
                content(mode).frame(width: s.width, height: s.height, alignment: .top)
            } else {
                content(mode)
                    .frame(width: s.width, height: s.height, alignment: .top)
                    .clipShape(NotchShape(top: 0, bottom: br))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(m.opening ? Motion.open : Motion.close, value: mode)
        .animation(Motion.hover, value: m.hover)
        .animation(Motion.open, value: m.activities.count)
        .animation(Motion.hover, value: m.activities.last?.action)
        .animation(Motion.close, value: m.notch)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    func content(_ mode: IslandModel.Mode) -> some View {
        switch mode {
        case .idle:
            /* в покое — искра Claude слева от выреза, на месте обложки */
            HStack {
                if m.claudeRunning { Spark(state: .idle).frame(width: 16, height: 16) }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: m.notch.height)
            .transition(.island)
        case .music:
            HStack {
                Artwork(image: m.art, size: 20, radius: 5)
                    .matchedGeometryEffect(id: "art", in: ns)
                Spacer()
                /* искра Claude или эквалайзер — в настройках плеера */
                /* Claude закрыт — вместо искры эквалайзер */
                if Prefs.rightIcon == "bars" || !m.claudeRunning { Bars(playing: true).frame(width: 18, height: 12) }
                else { Spark(state: .music).frame(width: 16, height: 16) }
            }
            .padding(.horizontal, 12)
            .frame(height: m.notch.height)
            .transition(.island)
        case .working:
            WorkingWing(m: m)
                .transition(.island)
        case .flash:
            HStack {
                Image(systemName: "bolt.fill").foregroundStyle(.green)
                Text(L("Зарядка", "Charging")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text("\(m.battery.level)%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 14)
            .frame(height: m.notch.height)
            .transition(.island)
        case .focus:
            if let e = m.focusEvent {
                FocusWing(e: e)
                    .frame(height: m.notch.height)
                    .id(e.mode.id + (e.on ? "1" : "0"))
                    .transition(.island)
            }
        case .volume:
            VolumeWing(s: m.sound, notch: m.notch)
                .transition(.island)
        case .device:
            if let d = m.connected {
                if d.airpods {
                    AirPodsWing(d: d, notch: m.notch)
                        .contentShape(Rectangle())
                        .onTapGesture { m.openSoundMenu() }
                        .id("\(d.id)-\(d.inCase)")
                        .transition(.island)
                } else {
                    DeviceWing(d: d)
                        .frame(height: m.notch.height)
                        .id(d.id)
                        .transition(.island)
                }
            }
        case .notice:
            if let n = m.notice {
                NoticeView(n: n, notch: m.notch)
                    .contentShape(Rectangle())
                    .onTapGesture { m.openNotice() }
                    .id(n.id)
                    .transition(.island)
            }
        case .expanded:
            Expanded(m: m, ns: ns).transition(.island)
        }
    }
}

/* Claude Code работает: под чёлкой одной строкой по центру — искра, проект, что делается, время. */
struct WorkingWing: View {
    @ObservedObject var m: IslandModel
    var body: some View {
        let a = m.activities.last
        VStack(spacing: 0) {
            /* если играет музыка — плеер остаётся по бокам чёлки */
            /* музыка: обложка слева, искра справа; без музыки искра слева. Пока Claude работает — искра вращается */
            HStack {
                if m.musicOn {
                    Artwork(image: m.art, size: 20, radius: 5)
                    Spacer()
                    Spark(state: .working).frame(width: 16, height: 16)
                } else {
                    /* музыки нет — искра слева, на месте обложки */
                    Spark(state: .working).frame(width: 16, height: 16)
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: m.notch.height)
            HStack(spacing: 6) {
                /* вместо названия проекта — значок Claude */
                Spark(state: .working).frame(width: 12, height: 12)
                Text(a?.action ?? L("Думаю…", "Thinking…"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(a?.action ?? "")
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(spacing: 4) {
                        if m.activities.count > 1 {
                            Text("×\(m.activities.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        if let a {
                            Text(clock(ctx.date.timeIntervalSince(a.started)))
                                .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(sparkColor)
                        }
                    }
                    .fixedSize()
                }
            }
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .clipped()
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: a?.action)
            Spacer(minLength: 0)
        }
    }
}

struct Spinner: View {
    var body: some View {
        Live { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.68)
                .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360))
        }
    }
}

struct SourceIcon: View {
    let bundle: String?
    let size: CGFloat
    var body: some View {
        if let img = appIcon(bundle) {
            Image(nsImage: img).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.7, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: size, height: size)
        }
    }
}

struct NoticeView: View {
    let n: Notice
    let notch: CGSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(n.source).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(L("сейчас", "now")).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 22)
            .frame(height: notch.height)

            HStack(alignment: .center, spacing: 14) {
                /* иконка приложения, в углу — значок статуса */
                Group {
                    if let a = n.avatar {
                        /* аватарка отправителя, в углу — иконка приложения */
                        Image(nsImage: a).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40).clipShape(Circle())
                            .overlay(alignment: .bottomTrailing) {
                                SourceIcon(bundle: n.icon, size: 17)
                                    .background(Circle().fill(.black).padding(-1.5))
                                    .offset(x: 3, y: 3)
                            }
                    } else {
                        SourceIcon(bundle: n.icon, size: 40)
                    }
                }
                    .overlay(alignment: .bottomTrailing) {
                        if n.kind != .info {
                            Image(systemName: symbol)
                                .font(.system(size: 15, weight: .bold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, tint)
                                .background(Circle().fill(.black).padding(-2))
                                .offset(x: 4, y: 4)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(n.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if !n.body.isEmpty {
                        Text(n.body).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    var symbol: String {
        switch n.kind {
        case .done: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .info: return "bell.circle.fill"
        }
    }

    var tint: Color {
        switch n.kind {
        case .done: return .green
        case .attention: return accent
        case .info: return .white
        }
    }
}

struct Expanded: View {
    @ObservedObject var m: IslandModel
    let ns: Namespace.ID

    static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Lang.locale
        f.setLocalizedDateFormatFromTemplate("EEEdMMMM")
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Self.dateFmt.string(from: Date()).capitalized)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                OutputIcons(s: m.sound) { m.openSoundMenu() }
                BatteryLabel(b: m.battery)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 22)
            .frame(height: m.notch.height)

            Group {
                if let t = m.track {
                    Player(m: m, t: t, ns: ns)
                } else {
                    Clock()
                }
            }
            .frame(height: 84)
            .padding(.horizontal, 22)
            .padding(.top, 12)

            SoundSection(s: m.sound)
                .padding(.horizontal, 22)
                .padding(.top, 14)

            if !m.activities.isEmpty {
                /* что делает Claude — по центру */
                HStack(spacing: 8) {
                    ForEach(m.activities.suffix(3)) { a in Chip(a: a) }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 22)
                .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
    }
}

struct Chip: View {
    let a: Activity
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 6) {
                Spark(state: .working).frame(width: 13, height: 13)
                /* без названия проекта — только значок, что делается и время */
                Text(a.action).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Text(clock(ctx.date.timeIntervalSince(a.started)))
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(sparkColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.08)))
        }
    }
}

struct Player: View {
    @ObservedObject var m: IslandModel
    let t: Track
    let ns: Namespace.ID

    var body: some View {
        HStack(spacing: 14) {
            Artwork(image: m.art, size: 84, radius: 16)
                .matchedGeometryEffect(id: "art", in: ns)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 8) {
                    Text(t.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    /* «Добавить в медиатеку»: на линии названия, правый край вровень с концом полосы прогресса */
                    SaveButton(done: m.saved.contains(t.key), tint: t.app == "Spotify" ? spotifyGreen : accent) { m.saveTrack() }
                }
                .frame(height: 20)
                Text(t.artist).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let pos = t.now(ctx.date)
                    VStack(spacing: 4) {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.18))
                                Capsule().fill(accent)
                                    .frame(width: t.duration > 0 ? g.size.width * pos / t.duration : 0)
                                    .animation(.linear(duration: 0.5), value: pos)
                            }
                        }
                        .frame(height: 4)
                        HStack {
                            Text(clock(pos))
                            Spacer()
                            Text("−" + clock(max(0, t.duration - pos)))
                        }
                        .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }
            /* кнопки как в Spotify: перемешать, назад, пауза в белом круге, вперёд, повтор */
            let on = t.app == "Spotify" ? spotifyGreen : accent
            HStack(spacing: 6) {
                Btn("shuffle", 14, tint: t.shuffle ? on : .white.opacity(0.6), dot: t.shuffle) { m.control(.shuffle) }
                Btn("backward.end.fill", 17) { m.control(.previous) }
                Btn(t.playing ? "pause.fill" : "play.fill", 16, filled: true) { m.control(.toggle) }
                Btn("forward.end.fill", 17) { m.control(.next) }
                Btn(t.repeatMode == 2 ? "repeat.1" : "repeat", 14,
                    tint: t.repeatMode > 0 ? on : .white.opacity(0.6), dot: t.repeatMode > 0) { m.control(.repeatMode) }
            }
        }
    }
}

/* Маленькая кнопка «Добавить в медиатеку»: не раздувает строку названия. */
struct SaveButton: View {
    let done: Bool
    let tint: Color
    let action: () -> Void
    @State private var hover = false
    @State private var pop = false

    var body: some View {
        Image(systemName: done ? "checkmark.circle.fill" : "plus.circle")
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(done ? tint : .white.opacity(hover ? 0.95 : 0.6))
            .frame(width: 20, height: 20)
            .scaleEffect(pop ? 1.25 : (hover ? 1.08 : 1))
            .contentShape(Circle())
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
            .onTapGesture {
                action()
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { pop = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pop = false }
                }
            }
            .help(L("Добавить в медиатеку", "Add to library"))
    }
}

struct Btn: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    var tint: Color = .white
    var dot = false
    var filled = false
    @State private var hover = false
    @State private var pressed = false

    init(_ icon: String, _ size: CGFloat, tint: Color = .white, dot: Bool = false, filled: Bool = false,
         action: @escaping () -> Void) {
        self.icon = icon; self.size = size; self.action = action
        self.tint = tint; self.dot = dot; self.filled = filled
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size, weight: filled ? .bold : .semibold))
            .foregroundStyle(filled ? Color.black : tint)
            .frame(width: size + (filled ? 22 : 16), height: size + (filled ? 22 : 16))
            .background(Circle().fill(filled ? Color.white : .white.opacity(hover ? 0.12 : 0)))
            .overlay(alignment: .bottom) {
                if dot { Circle().fill(tint).frame(width: 4, height: 4).offset(y: 2) }
            }
            .scaleEffect(pressed ? 0.82 : 1)
            .contentShape(Circle())
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { pressed = true } } }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { pressed = false }
                        action()
                    }
            )
    }
}

struct Clock: View {
    static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Lang.locale
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(alignment: .firstTextBaseline) {
                Text(Self.timeFmt.string(from: ctx.date))
                    .font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit()
                Spacer()
                Text(L("Ничего не играет", "Nothing playing"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }
}

struct BatteryLabel: View {
    let b: Battery
    var body: some View {
        if b.present {
            HStack(spacing: 5) {
                Text("\(b.level)%").font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: icon)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(color, .white.opacity(0.5))
                    .font(.system(size: 14))
            }
        }
    }
    var icon: String {
        if b.charging || b.plugged { return "battery.100percent.bolt" }
        switch b.level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
    var color: Color {
        if b.charging || b.plugged { return .green }
        return b.level <= 20 ? .red : .white
    }
}

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.45, weight: .semibold))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/* Эквалайзер в «ухе» справа. */
struct Bars: View {
    let playing: Bool
    var body: some View {
        Live(paused: !playing) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let k = playing ? 0.35 + 0.65 * abs(sin(t * (3.1 + Double(i) * 1.3) + Double(i))) : 0.2
                    Capsule().fill(accent).frame(width: 3, height: 12 * k)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}


/* Подключились наушники: иконка модели слева, заряд справа. */
struct DeviceWing: View {
    let d: OutputDevice
    @State private var shown = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: d.symbol)
                .font(.system(size: 17, weight: .medium))
                .scaleEffect(shown ? 1 : 0.4)
                .opacity(shown ? 1 : 0)
            Spacer()
            if let b = d.battery {
                Text("\(b)%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(b <= 20 ? .red : .green)
                Ring(level: Double(b) / 100, color: b <= 20 ? .red : .green)
                    .frame(width: 14, height: 14)
            } else {
                Text(L("Подключены", "Connected")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.12)) { shown = true }
        }
    }
}

/* AirPods подключились: под вырезом крутятся объёмные наушники. Нажатие — меню «Звук». */
struct AirPodsWing: View {
    let d: OutputDevice
    let notch: CGSize
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height)
            if d.symbol == "airpods.max" {
                AirPodsArt(d: d).frame(height: 40)
            } else {
                /* настоящая 3D-модель со светом и бликами */
                AirPods3D(pro: d.symbol == "airpods.pro", inCase: d.inCase)
                    .frame(width: 84, height: 50)
                    .scaleEffect(shown ? 1 : 0.4)
                    .opacity(shown ? 1 : 0)
                    .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.08)) { shown = true } }
            }
            Spacer(minLength: 0)
        }
    }
}

func budSymbol(_ d: OutputDevice, left: Bool) -> String {
    let pro = d.symbol == "airpods.pro"
    return (pro ? "airpodpro." : "airpod.") + (left ? "left" : "right")
}

func caseSymbol(_ d: OutputDevice) -> String {
    switch d.symbol {
    case "airpods.pro": return "airpodspro.chargingcase.wireless.fill"
    case "airpods.gen3": return "airpods.gen3.chargingcase.wireless.fill"
    case "airpods.gen4": return "airpods.gen4.chargingcase.wireless.fill"
    default: return "airpods.chargingcase.fill"
    }
}

/* Заряд одной части: кольцо, внутри значок, под ним проценты. */
struct Charge: View {
    let level: Int
    let symbol: String
    var color: Color { level <= 20 ? .red : .green }
    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Ring(level: Double(level) / 100, color: color).frame(width: 26, height: 26)
                Image(systemName: symbol).font(.system(size: 10, weight: .medium))
            }
            Text("\(level)%").font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/* Объёмные наушники или кейс (смотря где наушники): плавно поворачиваются, с тенью и светотенью. */
struct AirPodsArt: View {
    let d: OutputDevice
    @State private var shown = false

    /* только наушники, без кейса */
    var symbol: String { d.symbol }

    var body: some View {
        Live { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.55), radius: 4, y: 1)  /* читается и на светлых окнах */
                .rotation3DEffect(.degrees(t * 90), axis: (0, 1, 0), perspective: 0.45)
                .scaleEffect(shown ? 1 : 0.5)
                .opacity(shown ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1)) { shown = true } }
    }
}

struct Ring: View {
    let level: Double
    let color: Color
    @State private var drawn = 0.0
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
            Circle().trim(from: 0, to: drawn)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear { withAnimation(.easeOut(duration: 0.8).delay(0.2)) { drawn = level } }
    }
}

/* Звук: громкость и выбор выхода — как в меню «Звук». */
struct SoundSection: View {
    @ObservedObject var s: SoundSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: s.muted || s.volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(width: 16)
                    .contentShape(Rectangle())
                    .onTapGesture { s.setMuted(!s.muted) }
                VolumeSlider(value: s.muted ? 0 : Double(s.volume)) { s.setVolume(Float($0)) }
                    .frame(height: 22)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

struct VolumeSlider: View {
    let value: Double
    let onChange: (Double) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let h: CGFloat = dragging ? 10 : 6
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().fill(.white).frame(width: max(h, g.size.width * value))
            }
            .frame(height: h)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !dragging { withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { dragging = true } }
                        onChange(Double(min(max(0, v.location.x / g.size.width), 1)))
                    }
                    .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragging = false } }
            )
        }
    }
}

/* Выходы звука — маленькие иконки в верхней строке рядом с батареей. Клик переключает выход. */
struct OutputIcons: View {
    @ObservedObject var s: SoundSystem
    var onMenu: () -> Void = { SoundMenu.open() }
    var body: some View {
        HStack(spacing: 4) {
            ForEach(s.outputs) { d in
                OutputIcon(d: d, active: d.id == s.current) {
                    /* уже выбранные наушники — открыть меню с их режимами */
                    if d.id == s.current && d.bluetooth { onMenu() }
                    else { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { s.select(d.id) } }
                }
            }
        }
    }
}

struct OutputIcon: View {
    let d: OutputDevice
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Image(systemName: d.symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(active ? .white : .white.opacity(0.6))
            .frame(width: 20, height: 20)
            .background(Circle().fill(active ? Color.blue : .white.opacity(hover ? 0.2 : 0.1)))
            .scaleEffect(hover ? 1.12 : 1)
            .contentShape(Circle())
            .help(d.builtIn ? L("Динамики MacBook", "MacBook Speakers") : d.name + (d.battery.map { " · \($0)%" } ?? ""))
            .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { hover = h } }
            .onTapGesture(perform: action)
    }
}


/* Громкость: чёлка вытягивается вниз, под камерой — значок, полоса и проценты. */
struct VolumeWing: View {
    @ObservedObject var s: SoundSystem
    let notch: CGSize
    var level: Double { s.muted ? 0 : Double(s.volume) }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height)
            HStack(spacing: 10) {
                ZStack {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .id(icon)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                .frame(width: 20, alignment: .leading)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(level == 0 ? Color.white.opacity(0.4) : .white)
                            .frame(width: max(6, g.size.width * level))
                    }
                }
                .frame(height: 6)
                Text("\(Int((level * 100).rounded()))")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .frame(height: 26)
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: level)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: icon)
    }

    var icon: String {
        if level == 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

/* Включили режим фокуса: значок режима его цветом слева, название справа. */
struct FocusWing: View {
    let e: IslandModel.FocusEvent
    @State private var shown = false

    var body: some View {
        let tint = FocusWatcher.color(e.mode.tint, id: e.mode.id)
        HStack(spacing: 8) {
            Image(systemName: e.mode.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(e.on ? tint : .white.opacity(0.45))
                .rotationEffect(.degrees(shown ? 0 : -40))
                .scaleEffect(shown ? 1 : 0.4)
                .opacity(shown ? 1 : 0)
            Spacer()
            Text(e.mode.name)
                .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                .foregroundStyle(e.on ? tint : .white.opacity(0.6))
            Text(e.on ? L("вкл", "on") : L("выкл", "off"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.12)) { shown = true }
        }
    }
}
