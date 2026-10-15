// Renders the app icon: `swift scripts/make-icon.swift Resources/AppIcon.png`
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Body (Apple's grid: 824pt squircle inset 100pt), with drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x000000, 0.45))
ctx.addPath(roundedRect(body, 185)); ctx.setFillColor(color(0x0B0B0D)); ctx.fillPath()
ctx.restoreGState()

// Subtle top-lit gradient + hairline rim.
ctx.saveGState()
ctx.addPath(roundedRect(body, 185)); ctx.clip()
let sheen = CGGradient(colorsSpace: nil, colors: [color(0x2C2C30), color(0x0B0B0D)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 420), options: [])
ctx.restoreGState()
ctx.addPath(roundedRect(body.insetBy(dx: 2, dy: 2), 183)); ctx.setStrokeColor(color(0xFFFFFF, 0.14)); ctx.setLineWidth(4); ctx.strokePath()

// Three mini widget cards.
let gap: CGFloat = 36, inset: CGFloat = 92
let cardW = (824 - inset * 2 - gap) / 2
let top = CGRect(x: 100 + inset, y: 100 + inset + cardW * 0.78 + gap, width: cardW, height: cardW)
let topRight = top.offsetBy(dx: cardW + gap, dy: 0)
let wide = CGRect(x: 100 + inset, y: 100 + inset, width: cardW * 2 + gap, height: cardW * 0.78)
for card in [top, topRight, wide] {
    ctx.addPath(roundedRect(card, 58)); ctx.setFillColor(color(0x1E1E21)); ctx.fillPath()
    ctx.addPath(roundedRect(card.insetBy(dx: 1.5, dy: 1.5), 57)); ctx.setStrokeColor(color(0xFFFFFF, 0.10)); ctx.setLineWidth(3); ctx.strokePath()
}

// Card 1: usage ring.
let ringCenter = CGPoint(x: top.midX, y: top.midY)
let ringRadius = top.width * 0.30
ctx.setLineWidth(top.width * 0.085); ctx.setLineCap(.round)
ctx.setStrokeColor(color(0xFFFFFF, 0.12)); ctx.addArc(center: ringCenter, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false); ctx.strokePath()
ctx.setStrokeColor(color(0xFFFFFF)); ctx.addArc(center: ringCenter, radius: ringRadius, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 2 * 0.68, clockwise: true); ctx.strokePath()

// Card 2: clock.
let clockCenter = CGPoint(x: topRight.midX, y: topRight.midY)
let clockRadius = topRight.width * 0.33
ctx.setLineWidth(4); ctx.setStrokeColor(color(0xFFFFFF, 0.25))
ctx.addArc(center: clockCenter, radius: clockRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false); ctx.strokePath()
for i in 0..<12 {
    let a = CGFloat(i) / 12 * .pi * 2
    let r1 = clockRadius * (i % 3 == 0 ? 0.74 : 0.84), r2 = clockRadius * 0.92
    ctx.move(to: CGPoint(x: clockCenter.x + sin(a) * r1, y: clockCenter.y + cos(a) * r1))
    ctx.addLine(to: CGPoint(x: clockCenter.x + sin(a) * r2, y: clockCenter.y + cos(a) * r2))
}
ctx.setLineWidth(6); ctx.setStrokeColor(color(0xFFFFFF, 0.6)); ctx.strokePath()
func hand(_ angle: CGFloat, _ length: CGFloat, _ width: CGFloat, _ c: CGColor) {
    ctx.move(to: clockCenter)
    ctx.addLine(to: CGPoint(x: clockCenter.x + sin(angle) * length, y: clockCenter.y + cos(angle) * length))
    ctx.setLineWidth(width); ctx.setStrokeColor(c); ctx.strokePath()
}
hand(.pi * 2 * (10.15 / 12), clockRadius * 0.5, 16, color(0xFFFFFF))
hand(.pi * 2 * (10 / 60), clockRadius * 0.75, 11, color(0xFFFFFF))
hand(.pi * 2 * (38 / 60), clockRadius * 0.82, 5, color(0xFF453A))
ctx.addEllipse(in: CGRect(x: clockCenter.x - 12, y: clockCenter.y - 12, width: 24, height: 24)); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()

// Card 3: sparkline with soft fill.
let values: [CGFloat] = [0.30, 0.42, 0.36, 0.58, 0.47, 0.72, 0.55, 0.66, 0.50, 0.80]
let plot = wide.insetBy(dx: 56, dy: 52)
let points = values.enumerated().map { CGPoint(x: plot.minX + plot.width * CGFloat($0.offset) / CGFloat(values.count - 1),
                                               y: plot.minY + plot.height * $0.element) }
let line = CGMutablePath()
line.move(to: points[0])
for i in 1..<points.count {
    let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
    if i == 1 { line.addLine(to: mid) } else { line.addQuadCurve(to: mid, control: points[i - 1]) }
}
line.addLine(to: points.last!)
let area = line.mutableCopy()!
area.addLine(to: CGPoint(x: plot.maxX, y: wide.minY + 20)); area.addLine(to: CGPoint(x: plot.minX, y: wide.minY + 20)); area.closeSubpath()
ctx.saveGState()
ctx.addPath(area); ctx.clip()
let fill = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: plot.maxY), end: CGPoint(x: 0, y: wide.minY), options: [])
ctx.restoreGState()
ctx.addPath(line); ctx.setStrokeColor(color(0xFFFFFF)); ctx.setLineWidth(12); ctx.setLineJoin(.round); ctx.setLineCap(.round); ctx.strokePath()
ctx.addEllipse(in: CGRect(x: points.last!.x - 16, y: points.last!.y - 16, width: 32, height: 32)); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
