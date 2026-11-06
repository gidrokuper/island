/* Рисует иконку острова: swift make-icon.swift <out.png> */
import AppKit

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

/* подложка-«сквиркл» по сетке macOS: 824×824 с отступом 100 */
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
ctx.saveGState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.black.setFill()
squircle.fill()
ctx.restoreGState()

squircle.addClip()
NSGradient(colors: [NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.19, alpha: 1),
                    NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)])!
    .draw(in: body, angle: -90)

/* тёплое свечение снизу */
let glow = NSGradient(colors: [NSColor(calibratedRed: 1, green: 0.48, blue: 0.13, alpha: 0.35),
                               NSColor(calibratedRed: 1, green: 0.48, blue: 0.13, alpha: 0)])!
glow.draw(fromCenter: NSPoint(x: 512, y: 120), radius: 0, toCenter: NSPoint(x: 512, y: 120), radius: 520, options: [])

/* сам остров — чёрная капсула у верхнего края */
let pill = NSRect(x: 232, y: 560, width: 560, height: 170)
let pillPath = NSBezierPath(roundedRect: pill, xRadius: 85, yRadius: 85)
ctx.saveGState()
let ps = NSShadow()
ps.shadowColor = NSColor.black.withAlphaComponent(0.6)
ps.shadowBlurRadius = 30
ps.shadowOffset = NSSize(width: 0, height: -12)
ps.set()
NSColor.black.setFill()
pillPath.fill()
ctx.restoreGState()
NSColor.white.withAlphaComponent(0.08).setStroke()
pillPath.lineWidth = 3
pillPath.stroke()

let orange = NSColor(calibratedRed: 1, green: 0.48, blue: 0.13, alpha: 1)
/* слева — точка-«камера» с оранжевым ободком */
let dot = NSRect(x: 300, y: 610, width: 70, height: 70)
orange.setFill()
NSBezierPath(ovalIn: dot).fill()
NSColor.black.setFill()
NSBezierPath(ovalIn: dot.insetBy(dx: 16, dy: 16)).fill()
/* справа — эквалайзер */
let heights: [CGFloat] = [56, 100, 72, 112, 48]
for (i, h) in heights.enumerated() {
    let x = 520 + CGFloat(i) * 42
    let r = NSRect(x: x, y: 645 - h / 2, width: 22, height: h)
    orange.setFill()
    NSBezierPath(roundedRect: r, xRadius: 11, yRadius: 11).fill()
}

/* полоска-«плеер» под островом */
NSColor.white.withAlphaComponent(0.14).setFill()
NSBezierPath(roundedRect: NSRect(x: 262, y: 380, width: 500, height: 22), xRadius: 11, yRadius: 11).fill()
orange.setFill()
NSBezierPath(roundedRect: NSRect(x: 262, y: 380, width: 300, height: 22), xRadius: 11, yRadius: 11).fill()

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
