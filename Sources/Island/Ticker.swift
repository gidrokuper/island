import SwiftUI

/*
 Общий таймер анимаций (30 кадров/с) в режиме .common: не засыпает, когда окно острова
 неактивно и когда открыто меню. TimelineView(.animation) в таком окне иногда замирал.
*/
final class Ticker: ObservableObject {
    static let shared = Ticker()
    @Published private(set) var now = Date()
    private init() {
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.now = Date() }
        RunLoop.main.add(t, forMode: .common)
    }
}

struct LiveContext { let date: Date }

/* Замена TimelineView(.animation): Live { ctx in … ctx.date … } */
struct Live<Content: View>: View {
    var paused = false
    @ViewBuilder let content: (LiveContext) -> Content
    var body: some View {
        if paused { content(LiveContext(date: Date())) } else { Running(content: content) }
    }

    private struct Running: View {
        @ObservedObject private var tick = Ticker.shared
        let content: (LiveContext) -> Content
        var body: some View { content(LiveContext(date: tick.now)) }
    }
}
