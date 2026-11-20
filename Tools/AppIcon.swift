import SwiftUI
import AppKit

// Renders the Lumora app icon: Pell, the companion moon, with Lumora's gold
// orbit and four-point star. Pell's geometry is copied from PellPainter.
// usage: swift Tools/AppIcon.swift <out-dir> [calm|happy|proud]; the shipped icon is "happy".

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

let warmGold: UInt32 = 0xFFD58A
let ink = Color(hex: 0x2A2F4E)

func glow(_ ctx: inout GraphicsContext, at p: CGPoint, radius: CGFloat, color: Color, intensity: Double) {
    let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
    ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
        Gradient(stops: [.init(color: color.opacity(intensity), location: 0),
                         .init(color: color.opacity(intensity * 0.35), location: 0.35),
                         .init(color: color.opacity(0), location: 1)]),
        center: p, startRadius: 0, endRadius: radius))
}

func sparkle(_ ctx: inout GraphicsContext, at c: CGPoint, size r: CGFloat, color: Color) {
    var s = Path()
    let w = r * 0.2
    s.move(to: CGPoint(x: c.x, y: c.y - r))
    s.addLine(to: CGPoint(x: c.x + w, y: c.y - w)); s.addLine(to: CGPoint(x: c.x + r, y: c.y))
    s.addLine(to: CGPoint(x: c.x + w, y: c.y + w)); s.addLine(to: CGPoint(x: c.x, y: c.y + r))
    s.addLine(to: CGPoint(x: c.x - w, y: c.y + w)); s.addLine(to: CGPoint(x: c.x - r, y: c.y))
    s.addLine(to: CGPoint(x: c.x - w, y: c.y - w)); s.closeSubpath()
    ctx.fill(s, with: .color(color))
}

func pell(_ ctx: inout GraphicsContext, center c: CGPoint, radius r: CGFloat, expression: String) {
    let s = r / 64
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: c.x + (x - 100) * s, y: c.y + (y - 100) * s) }
    func oval(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x + (x - 100 - rx) * s, y: c.y + (y - 100 - ry) * s, width: rx * 2 * s, height: ry * 2 * s))
    }
    func line(_ a: (Double, Double), _ b: (Double, Double), quad q: (Double, Double), width: Double = 3.2) {
        var path = Path()
        path.move(to: p(a.0, a.1)); path.addQuadCurve(to: p(b.0, b.1), control: p(q.0, q.1))
        ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round))
    }
    func eye(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
        ctx.fill(oval(x, y, rx, ry), with: .color(ink))
        ctx.fill(oval(x + 1.8, y - 2.2, 1.8, 1.8), with: .color(.white))
    }

    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .radialGradient(
        Gradient(stops: [.init(color: .white, location: 0), .init(color: Color(hex: 0xDCE3EE), location: 0.55),
                         .init(color: Color(hex: 0x8D97AE), location: 1)]),
        center: p(78, 76), startRadius: 0, endRadius: r * 1.56))
    for (x, y, rr, a) in [(72.0, 68.0, 9.0, 0.35), (134, 124, 6, 0.35), (127, 64, 4, 0.3)] {
        ctx.fill(oval(x, y, rr, rr), with: .color(Color(hex: 0x8D97AE).opacity(a)))
    }
    for x in [70.0, 130] { ctx.fill(oval(x, 114, 10, 6), with: .color(Color(hex: 0xFF9BB8).opacity(0.5))) }

    switch expression {
    case "happy":
        line((75, 101), (89, 101), quad: (82, 91), width: 3.6)
        line((111, 101), (125, 101), quad: (118, 91), width: 3.6)
        var mouth = Path()
        mouth.move(to: p(88, 113)); mouth.addQuadCurve(to: p(112, 113), control: p(100, 130)); mouth.closeSubpath()
        ctx.fill(mouth, with: .color(ink))
        var tongue = Path()
        tongue.move(to: p(94, 121)); tongue.addQuadCurve(to: p(106, 121), control: p(100, 126))
        tongue.addQuadCurve(to: p(94, 121), control: p(100, 118))
        ctx.fill(tongue, with: .color(Color(hex: 0xFF9BB8)))
    case "proud":
        line((76, 99), (88, 99), quad: (82, 93), width: 3.4)
        line((112, 99), (124, 99), quad: (118, 93), width: 3.4)
        line((86, 113), (114, 113), quad: (100, 127), width: 3.4)
    default: // calm
        eye(82, 98, 5, 6.5); eye(118, 98, 5, 6.5)
        line((92, 116), (108, 116), quad: (100, 122))
    }
}

struct Icon: View {
    var expression: String
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            // Sky
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x2B2A66), Color(hex: 0x1C1A48), Color(hex: 0x0D0E2A)]),
                startPoint: .zero, endPoint: CGPoint(x: w * 0.6, y: w)))
            glow(&ctx, at: CGPoint(x: w * 0.18, y: w * 0.82), radius: w * 0.6, color: Color(hex: 0x6E3E86), intensity: 0.45)
            glow(&ctx, at: CGPoint(x: w * 0.5, y: w * 0.47), radius: w * 0.55, color: Color(hex: 0x8B7CFF), intensity: 0.35)
            var seed: UInt64 = 7
            func rand() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
            for _ in 0..<70 {
                let x = rand() * w, y = rand() * w, r = (0.8 + rand() * 2.6) * w / 1024, a = 0.25 + rand() * 0.6
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(a)))
            }

            let c = CGPoint(x: w * 0.5, y: w * 0.47)
            let r = w * 0.27
            // Orbit: a tilted ellipse, back half behind Pell, front half over.
            let orbit = Path(ellipseIn: CGRect(x: -w * 0.43, y: -w * 0.1, width: w * 0.86, height: w * 0.2))
                .applying(CGAffineTransform(rotationAngle: -0.22).concatenating(CGAffineTransform(translationX: c.x, y: c.y + w * 0.1)))
            let gold = StrokeStyle(lineWidth: w * 0.014, lineCap: .round)
            let back = ctx
            back.stroke(orbit, with: .color(Color(hex: warmGold)), style: gold)

            glow(&ctx, at: c, radius: r * 1.7, color: Color(hex: 0xCFE3FF), intensity: 0.5)
            pell(&ctx, center: c, radius: r, expression: expression)

            var front = ctx
            front.clip(to: Path(CGRect(x: -w, y: c.y + w * 0.1, width: w * 3, height: w * 2)).applying(
                CGAffineTransform(translationX: -c.x, y: -c.y - w * 0.1).concatenating(CGAffineTransform(rotationAngle: -0.22))
                    .concatenating(CGAffineTransform(translationX: c.x, y: c.y + w * 0.1))))
            front.clip(to: Path(ellipseIn: CGRect(x: c.x - r - 20, y: c.y - r - 20, width: r * 2 + 40, height: r * 2 + 40)))
            front.stroke(orbit, with: .color(Color(hex: warmGold)), style: gold)

            // Lumora's star riding the orbit.
            let t = -0.5
            let local = CGPoint(x: cos(t) * w * 0.43, y: sin(t) * w * 0.1)
            let star = local.applying(CGAffineTransform(rotationAngle: -0.22)).applying(CGAffineTransform(translationX: c.x, y: c.y + w * 0.1))
            glow(&ctx, at: star, radius: w * 0.11, color: Color(hex: warmGold), intensity: 0.7)
            sparkle(&ctx, at: star, size: w * 0.075, color: .white)
            sparkle(&ctx, at: CGPoint(x: w * 0.22, y: w * 0.2), size: w * 0.03, color: .white.opacity(0.85))
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render(_ expression: String, to url: URL) {
    let renderer = ImageRenderer(content: Icon(expression: expression))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    // Flatten to an opaque RGB bitmap (App Store icons may not have alpha).
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let expressions = CommandLine.arguments.count > 2 ? [CommandLine.arguments[2]] : ["calm", "happy", "proud"]
MainActor.assumeIsolated {
    for e in expressions { render(e, to: out.appendingPathComponent("icon-\(e).png")) }
}
