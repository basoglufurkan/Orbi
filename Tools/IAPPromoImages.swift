import SwiftUI
import AppKit

// Renders the three Orbi+ promoted In-App Purchase images (1024 × 1024, opaque RGB).
// App Review rejects identical images for different products, so each plan has its own scene:
//   monthly  — a crescent moon on a single orbit (one lunar month), cool teal
//   yearly   — a golden sun with twelve worlds on its orbit (twelve months), amber
//   lifetime — a spiral galaxy around an endless figure-eight orbit, violet and rose
// No text or prices, so one image serves every storefront.
// usage: swift Tools/IAPPromoImages.swift <out-dir>

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

enum Plan: String, CaseIterable { case monthly, yearly, lifetime }

struct Palette { let top: UInt32; let bottom: UInt32; let haze: UInt32; let accent: UInt32; let ring: UInt32 }

func palette(_ plan: Plan) -> Palette {
    switch plan {
    case .monthly: return Palette(top: 0x08202E, bottom: 0x040A14, haze: 0x2E8FA8, accent: 0xDFF6FF, ring: 0x7FD6E8)
    case .yearly: return Palette(top: 0x2A1608, bottom: 0x0B0610, haze: 0xD98A2B, accent: 0xFFE3A3, ring: 0xFFC766)
    case .lifetime: return Palette(top: 0x1E0B2E, bottom: 0x07040F, haze: 0xB04CC8, accent: 0xFFD9F2, ring: 0xD99CFF)
    }
}

struct RNG { var seed: UInt64
    mutating func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
}

func glow(_ ctx: inout GraphicsContext, at p: CGPoint, radius: CGFloat, color: Color, intensity: Double) {
    let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
    ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
        Gradient(stops: [.init(color: color.opacity(intensity), location: 0),
                         .init(color: color.opacity(intensity * 0.35), location: 0.35),
                         .init(color: color.opacity(0), location: 1)]),
        center: p, startRadius: 0, endRadius: radius))
}

func dot(_ ctx: inout GraphicsContext, _ p: CGPoint, _ r: CGFloat, _ color: Color) {
    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
}

func sparkle(_ ctx: inout GraphicsContext, at c: CGPoint, size r: CGFloat, color: Color) {
    var s = Path()
    let w = r * 0.2
    s.move(to: CGPoint(x: c.x, y: c.y - r))
    s.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + w, y: c.y - w))
    s.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + w, y: c.y + w))
    s.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - w, y: c.y + w))
    s.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - w, y: c.y - w))
    ctx.fill(s, with: .color(color))
}

struct Scene: View {
    let plan: Plan
    var body: some View {
        Canvas { ctx, size in
            let pal = palette(plan)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(hex: pal.top), Color(hex: pal.bottom)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            glow(&ctx, at: c, radius: 620, color: Color(hex: pal.haze), intensity: 0.45)

            var rng = RNG(seed: plan == .monthly ? 11 : plan == .yearly ? 23 : 37)
            for _ in 0..<320 {
                let p = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height)
                let r = 0.6 + rng.next() * 1.8
                dot(&ctx, p, r, Color.white.opacity(0.35 + rng.next() * 0.6))
            }

            switch plan {
            case .monthly: drawMonthly(&ctx, c, pal)
            case .yearly: drawYearly(&ctx, c, pal)
            case .lifetime: drawLifetime(&ctx, c, pal, &rng)
            }
        }
        .frame(width: 1024, height: 1024)
    }

    func drawMonthly(_ ctx: inout GraphicsContext, _ c: CGPoint, _ pal: Palette) {
        let ring = Color(hex: pal.ring), accent = Color(hex: pal.accent)
        // One tilted orbit with a single small world: one cycle.
        let orbit = Path(ellipseIn: CGRect(x: c.x - 360, y: c.y - 140, width: 720, height: 280))
        ctx.stroke(orbit.applying(rotation(-0.32, around: c)), with: .color(ring.opacity(0.75)), lineWidth: 3)
        let moonR: CGFloat = 190
        glow(&ctx, at: c, radius: 420, color: accent, intensity: 0.35)
        // Crescent: lit disc minus an offset shadow disc.
        let layer = ctx
        layer.drawLayer { l in
            l.fill(Path(ellipseIn: CGRect(x: c.x - moonR, y: c.y - moonR, width: moonR * 2, height: moonR * 2)),
                   with: .radialGradient(Gradient(colors: [accent, Color(hex: pal.ring)]),
                                         center: CGPoint(x: c.x - 70, y: c.y - 60), startRadius: 0, endRadius: moonR * 1.3))
            l.blendMode = .destinationOut
            l.fill(Path(ellipseIn: CGRect(x: c.x - moonR + 95, y: c.y - moonR - 40, width: moonR * 2, height: moonR * 2)),
                   with: .color(.black))
        }
        let planet = CGPoint(x: c.x + 330, y: c.y - 95).applying(rotationTransform(-0.32, around: c))
        glow(&ctx, at: planet, radius: 70, color: ring, intensity: 0.7)
        dot(&ctx, planet, 20, accent)
        sparkle(&ctx, at: CGPoint(x: c.x + 230, y: c.y + 250), size: 34, color: accent)
    }

    func drawYearly(_ ctx: inout GraphicsContext, _ c: CGPoint, _ pal: Palette) {
        let ring = Color(hex: pal.ring), accent = Color(hex: pal.accent)
        let r: CGFloat = 330
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                   with: .color(ring.opacity(0.7)), lineWidth: 3)
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.62, width: r * 1.24, height: r * 1.24)),
                   with: .color(ring.opacity(0.25)), style: StrokeStyle(lineWidth: 2, dash: [6, 10]))
        // The sun.
        glow(&ctx, at: c, radius: 380, color: ring, intensity: 0.55)
        dot(&ctx, c, 120, accent)
        glow(&ctx, at: c, radius: 150, color: .white, intensity: 0.8)
        // Twelve worlds, one per month, growing brighter around the year.
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi - .pi / 2
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            let size = 9 + CGFloat(i) * 1.4
            glow(&ctx, at: p, radius: size * 3.2, color: ring, intensity: 0.4 + Double(i) / 24)
            dot(&ctx, p, size, accent)
        }
    }

    func drawLifetime(_ ctx: inout GraphicsContext, _ c: CGPoint, _ pal: Palette, _ rng: inout RNG) {
        let ring = Color(hex: pal.ring), accent = Color(hex: pal.accent)
        // Spiral galaxy arms of soft stars.
        for arm in 0..<2 {
            for k in 0..<520 {
                let t = Double(k) / 520
                let a = t * 3.6 * .pi + Double(arm) * .pi
                let rad = 30 + t * 400
                let jitter = (rng.next() - 0.5) * 60 * t
                let p = CGPoint(x: c.x + cos(a) * (rad + jitter), y: c.y + sin(a) * (rad + jitter) * 0.62)
                let col = rng.next() < 0.5 ? ring : accent
                dot(&ctx, p, 0.8 + rng.next() * 2.4 * (1 - t * 0.6), col.opacity(0.85 - t * 0.5))
            }
        }
        glow(&ctx, at: c, radius: 300, color: ring, intensity: 0.6)
        // Endless figure-eight orbit (lemniscate).
        var path = Path()
        for i in 0...360 {
            let t = Double(i) / 360 * 2 * .pi
            let d = 1 + pow(sin(t), 2)
            let p = CGPoint(x: c.x + 400 * cos(t) / d, y: c.y + 400 * sin(t) * cos(t) / d)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        ctx.stroke(path, with: .color(accent.opacity(0.8)), lineWidth: 4)
        sparkle(&ctx, at: c, size: 120, color: .white)
        glow(&ctx, at: c, radius: 90, color: .white, intensity: 0.9)
        for t in [0.0, Double.pi] {
            let d = 1 + pow(sin(t), 2)
            let p = CGPoint(x: c.x + 400 * cos(t) / d, y: c.y + 400 * sin(t) * cos(t) / d)
            glow(&ctx, at: p, radius: 60, color: ring, intensity: 0.8)
            dot(&ctx, p, 16, accent)
        }
    }

    func rotationTransform(_ angle: Double, around c: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle).translatedBy(x: -c.x, y: -c.y)
    }
    func rotation(_ angle: Double, around c: CGPoint) -> CGAffineTransform { rotationTransform(angle, around: c) }
}

@MainActor func render(_ plan: Plan, to url: URL) {
    let renderer = ImageRenderer(content: Scene(plan: plan))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
MainActor.assumeIsolated {
    for plan in Plan.allCases { render(plan, to: out.appendingPathComponent("orbi-plus-\(plan.rawValue)-1024.png")) }
}
