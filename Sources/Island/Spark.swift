import SwiftUI

let sparkColor = Color(red: 0.86, green: 0.47, blue: 0.34)

/*
 Логотип острова — «искра»: лучи разной длины из центра.
 working — лучи дышат и искра медленно вращается; attention — пульсирует; done — вспышка.
*/
struct Spark: View {
    enum State { case idle, working, attention, done }
    var state: State = .working
    var color: Color = sparkColor

    private static let rays: [CGFloat] = [1.0, 0.72, 0.9, 0.66, 0.96, 0.7, 0.86, 0.62, 0.94, 0.68]

    var body: some View {
        Live(paused: state == .idle) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2
                let n = Self.rays.count
                let spin: Double = state == .working ? t * 0.9 : 0
                let pulse: CGFloat = state == .attention ? 0.82 + 0.18 * CGFloat(abs(sin(t * 3.2))) : 1
                for i in 0..<n {
                    var len = Self.rays[i]
                    if state == .working {
                        len *= 0.72 + 0.28 * CGFloat((sin(t * 4.2 + Double(i) * 1.7) + 1) / 2)
                    }
                    len *= pulse
                    let a = Double(i) / Double(n) * 2 * .pi + spin
                    let w = r * 0.2
                    let inner = r * 0.16
                    let outer = max(inner + w, r * len)
                    var p = Path()
                    p.addRoundedRect(in: CGRect(x: inner, y: -w / 2, width: outer - inner, height: w),
                                     cornerSize: CGSize(width: w / 2, height: w / 2))
                    let tr = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: a)
                    g.fill(p.applying(tr), with: .color(color))
                }
                let core = r * 0.3
                g.fill(Path(ellipseIn: CGRect(x: c.x - core / 2, y: c.y - core / 2, width: core, height: core)),
                       with: .color(color))
            }
        }
    }
}
