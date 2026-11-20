import SwiftUI
import AppKit

// Renders LaunchPell: Pell asleep (calm face, eyes shut), the first frame of
// PellSplash, for the static launch screen. Geometry is copied from
// PellPainter and CelestialPainter.glow; keep them in step.
// usage: swift Tools/LaunchImage.swift Lumora/Resources/Assets.xcassets/LaunchPell.imageset

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

let side: CGFloat = 240   // points
let radius: CGFloat = 56  // PellSplash.moonRadius
let ink = Color(hex: 0x2A2F4E)

func glow(_ ctx: inout GraphicsContext, at p: CGPoint, radius: CGFloat, color: Color, intensity: Double) {
    let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
    ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
        Gradient(stops: [.init(color: color.opacity(intensity), location: 0),
                         .init(color: color.opacity(intensity * 0.35), location: 0.35),
                         .init(color: color.opacity(0), location: 1)]),
        center: p, startRadius: 0, endRadius: radius))
}

func asleep(_ ctx: inout GraphicsContext, center c: CGPoint, radius r: CGFloat) {
    let s = r / 64
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: c.x + (x - 100) * s, y: c.y + (y - 100) * s) }
    func oval(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x + (x - 100 - rx) * s, y: c.y + (y - 100 - ry) * s, width: rx * 2 * s, height: ry * 2 * s))
    }
    func line(_ a: (Double, Double), _ b: (Double, Double), quad q: (Double, Double), width: Double) {
        var path = Path()
        path.move(to: p(a.0, a.1)); path.addQuadCurve(to: p(b.0, b.1), control: p(q.0, q.1))
        ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round))
    }

    glow(&ctx, at: c, radius: r * 1.5, color: Color(hex: 0xCFE3FF), intensity: 0.38)
    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .radialGradient(
        Gradient(stops: [.init(color: .white, location: 0), .init(color: Color(hex: 0xDCE3EE), location: 0.55),
                         .init(color: Color(hex: 0x8D97AE), location: 1)]),
        center: p(78, 76), startRadius: 0, endRadius: r * 1.56))
    for (x, y, rr, a) in [(72.0, 68.0, 9.0, 0.35), (134, 124, 6, 0.35), (127, 64, 4, 0.3)] {
        ctx.fill(oval(x, y, rr, rr), with: .color(Color(hex: 0x8D97AE).opacity(a)))
    }
    for x in [70.0, 130] { ctx.fill(oval(x, 114, 10, 6), with: .color(Color(hex: 0xFF9BB8).opacity(0.45))) }
    // Calm, blink = 1: shut eyes, soft smile.
    for (x, rx) in [(82.0, 5.0), (118, 5)] { line((x - rx - 1, 98), (x + rx + 1, 98), quad: (x, 101), width: 3) }
    line((92, 116), (108, 116), quad: (100, 122), width: 3.2)
}

@MainActor func render(scale: CGFloat, to url: URL) {
    let view = Canvas { ctx, size in asleep(&ctx, center: CGPoint(x: size.width / 2, y: size.height / 2), radius: radius) }
        .frame(width: side, height: side)
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
MainActor.assumeIsolated {
    for k in 1...3 { render(scale: CGFloat(k), to: out.appendingPathComponent("LaunchPell@\(k)x.png")) }
}
let images = (1...3).map { #"    { "filename" : "LaunchPell@\#($0)x.png", "idiom" : "universal", "scale" : "\#($0)x" }"# }
try! """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

""".write(to: out.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
