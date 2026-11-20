import SwiftUI

/// Where today's orbit runs: a slow serpentine from dawn at the top to night
/// at the bottom, stops alternating left and right. Positions are measured in
/// stops (see `DayTimeline.cursor`): `-1` is dawn, `count` is night.
struct OrbitRoute: Equatable {
    var width: CGFloat
    var count: Int
    var spacing: CGFloat = 132
    var inset: CGFloat = 64

    var amplitude: CGFloat { min(width * 0.26, 150) }
    var height: CGFloat { inset * 2 + spacing * CGFloat(count + 1) }
    var center: CGFloat { width / 2 }

    func point(_ t: Double) -> CGPoint {
        let n = Double(count)
        // The route swings out to the stops and eases back to the middle at dawn and night.
        let envelope: Double
        if t < 0 {
            envelope = Self.smooth(t + 1)
        } else if t > n - 1 {
            envelope = Self.smooth(n - t)
        } else {
            envelope = 1
        }
        let x = center + amplitude * CGFloat(sin(.pi * (t + 0.5)) * envelope)
        return CGPoint(x: x, y: inset + spacing * CGFloat(t + 1))
    }

    /// The stop sits on the left half; its label goes to the right.
    func isLeft(_ stop: Int) -> Bool { point(Double(stop)).x < center }

    func path(from a: Double, to b: Double, step: Double = 0.025) -> Path {
        var path = Path()
        guard b > a else { return path }
        path.move(to: point(a))
        var t = a + step
        while t < b {
            path.addLine(to: point(t))
            t += step
        }
        path.addLine(to: point(b))
        return path
    }

    private static func smooth(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }
}

/// The living route: the travelled part glows violet to gold, the road ahead
/// is a slow drift of dashes, stops breathe, lit stops burn as stars, and a
/// comet marks now — circling the stop while its block runs, travelling
/// between stops in step with the free time. Reduce Motion stills it all.
struct OrbitRouteCanvas: View {
    var blocks: [PlanBlock]
    var route: OrbitRoute
    var selected: UUID?
    /// When each block was lit while the screen was open: a burst of light.
    var ignitions: [UUID: Date]
    /// When the screen appeared: the route draws itself in.
    var appeared: Date

    @Environment(AppModel.self) private var app
    @Environment(\.motionLevel) private var motion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if motion.animatesContinuously {
            TimelineView(.animation(minimumInterval: motion.frameInterval(30))) { context in
                canvas(at: context.date)
            }
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                canvas(at: context.date)
            }
        }
    }

    private func canvas(at date: Date) -> some View {
        Canvas { g, _ in
            draw(&g, now: app.clock.now, date: date)
        } symbols: {
            Image(systemName: "sunrise.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(LMColor.reward).tag("dawn")
            Image(systemName: "moon.stars.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(LMColor.focus).tag("night")
        }
        .frame(width: route.width, height: route.height)
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    /// `now` is the app's clock (what the plan shows); `date` is the frame's
    /// real time, which drives the motion.
    private func draw(_ g: inout GraphicsContext, now: Date, date: Date) {
        let timeline = DayTimeline(blocks: blocks, now: now)
        let n = timeline.blocks.count
        let animated = motion.animatesContinuously
        let t = date.timeIntervalSinceReferenceDate
        // The route draws itself in over the first moments on screen.
        let reveal = animated ? LMCurve.easeOutCubic.value(date.timeIntervalSince(appeared) / 1.6) : 1
        let end = -1 + Double(n + 1) * reveal
        let cursor = min(timeline.cursor, end)

        let violet = Color(hex: Palette.cosmicViolet), gold = Color(hex: Palette.warmGold), cyan = Color(hex: Palette.starlightCyan)
        let faint = colorScheme == .dark ? Color.white.opacity(0.28) : Color(hex: Palette.midnightIndigo).opacity(0.28)

        // The road ahead: a drift of dashes moving toward the future.
        if end > cursor {
            g.stroke(route.path(from: cursor, to: end), with: .color(faint),
                     style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1.5, 9], dashPhase: animated ? -t * 10 : 0))
        }
        // The road travelled: a soft glow under a violet → gold line.
        if cursor > -1 {
            let travelled = route.path(from: -1, to: cursor)
            g.stroke(travelled, with: .color(violet.opacity(0.18)), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
            g.stroke(travelled, with: .linearGradient(Gradient(colors: [violet, cyan, gold]),
                                                      startPoint: route.point(-1), endPoint: route.point(max(cursor, -0.5))),
                     style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }

        // Dawn and night beacons.
        drawBeacon(&g, symbol: "dawn", at: route.point(-1), tint: gold, visible: true)
        drawBeacon(&g, symbol: "night", at: route.point(Double(n)), tint: violet, visible: reveal >= 0.999)

        // Stops.
        for (k, block) in timeline.blocks.enumerated() {
            let shown = min(1, max(0, (end - Double(k)) * 2.5))
            guard shown > 0 else { continue }
            drawStop(&g, block: block, index: k, at: route.point(Double(k)), status: timeline.status(of: block),
                     progress: timeline.progress(of: block), scale: LMCurve.easeOutCubic.value(shown), t: t,
                     animated: animated, date: date)
        }

        // The comet.
        guard n > 0, reveal > 0.4 else { return }
        let active = timeline.blocks.indices.last { !timeline.blocks[$0].isCompleted && timeline.blocks[$0].contains(now) }
        if let k = active, Double(k) <= end {
            drawOrbitingComet(&g, around: route.point(Double(k)), t: t, animated: animated)
        } else {
            drawTravellingComet(&g, at: cursor, animated: animated, t: t)
        }
    }

    private func drawBeacon(_ g: inout GraphicsContext, symbol: String, at p: CGPoint, tint: Color, visible: Bool) {
        guard visible else { return }
        g.fill(Path(ellipseIn: CGRect(x: p.x - 22, y: p.y - 22, width: 44, height: 44)),
               with: .radialGradient(Gradient(colors: [tint.opacity(0.3), tint.opacity(0)]), center: p, startRadius: 0, endRadius: 22))
        if let image = g.resolveSymbol(id: symbol) { g.draw(image, at: p) }
    }

    private func drawStop(_ g: inout GraphicsContext, block: PlanBlock, index k: Int, at p: CGPoint, status: PlanBlockStatus,
                          progress: Double, scale: Double, t: Double, animated: Bool, date: Date) {
        let hue = block.category.color
        let gold = Color(hex: Palette.warmGold), cyan = Color(hex: Palette.starlightCyan)
        let isSelected = block.id == selected
        var r: CGFloat = 16 * scale

        // A light burst when the stop was lit while watching.
        if let lit = ignitions[block.id] {
            let dt = date.timeIntervalSince(lit)
            if dt >= 0, dt < 1.8 {
                let f = dt / 1.8
                let ring = 18 + 70 * LMCurve.easeOutExpo.value(f)
                g.stroke(circle(p, ring), with: .color(gold.opacity(0.7 * (1 - f))), lineWidth: 2.5 * (1 - f) + 0.5)
                for i in 0..<12 {
                    let a = Double(i) / 12 * 2 * .pi + Double(k)
                    let d = 22 + 56 * LMCurve.easeOutCubic.value(f)
                    let q = CGPoint(x: p.x + CGFloat(cos(a) * d), y: p.y + CGFloat(sin(a) * d))
                    g.fill(circle(q, 2.4 * (1 - f) + 0.4), with: .color(gold.opacity(1 - f)))
                }
                r *= 1 + 0.35 * (1 - f) * sin(f * .pi)
            }
        }

        if isSelected {
            g.stroke(circle(p, r + 9), with: .color(Color.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }

        switch status {
        case .upcoming:
            let breath = animated ? 1 + 0.06 * sin(t * 1.7 + Double(k)) : 1
            let rr = r * breath
            g.fill(circle(p, rr + 10), with: .radialGradient(Gradient(colors: [hue.opacity(0.22), hue.opacity(0)]),
                                                             center: p, startRadius: rr * 0.5, endRadius: rr + 10))
            g.fill(circle(p, rr), with: .color(hue.opacity(0.14)))
            g.stroke(circle(p, rr - 0.75), with: .color(hue), lineWidth: 1.5)
        case .active:
            // Sonar rings, a halo, and a ring filling with the block's time.
            if animated {
                for i in 0..<2 {
                    let phase = (t * 0.45 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    g.stroke(circle(p, r + 4 + 34 * phase), with: .color(cyan.opacity(0.45 * (1 - phase))), lineWidth: 1.5)
                }
            }
            g.fill(circle(p, r + 16), with: .radialGradient(Gradient(colors: [cyan.opacity(0.4), cyan.opacity(0)]),
                                                            center: p, startRadius: 0, endRadius: r + 16))
            g.stroke(circle(p, r + 5), with: .color(Color.white.opacity(0.14)), lineWidth: 3)
            var arc = Path()
            arc.addArc(center: p, radius: r + 5, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * progress), clockwise: false)
            g.stroke(arc, with: .color(cyan), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            g.fill(circle(p, r * 0.72), with: .color(hue))
            g.fill(circle(p, r * 0.3), with: .color(.white))
        case .lit:
            let glow = animated ? 0.85 + 0.15 * sin(t * 2.3 + Double(k) * 1.3) : 1
            g.fill(circle(p, r + 20), with: .radialGradient(Gradient(colors: [gold.opacity(0.5 * glow), gold.opacity(0)]),
                                                            center: p, startRadius: 0, endRadius: r + 20))
            var star = g
            star.translateBy(x: p.x, y: p.y)
            star.rotate(by: .radians(animated ? t * 0.12 + Double(k) : Double(k)))
            star.fill(StarShape.path(center: .zero, radius: r * 1.2, points: max(4, block.category.starPoints)), with: .color(gold))
            star.fill(StarShape.path(center: .zero, radius: r * 0.55, points: max(4, block.category.starPoints)), with: .color(.white.opacity(0.85)))
            // Two small glints that come and go.
            if animated {
                for i in 0..<2 {
                    let phase = (t * 0.3 + Double(i) * 0.5 + Double(k) * 0.17).truncatingRemainder(dividingBy: 1)
                    let a = Double(i) * 2.2 + Double(k)
                    let q = CGPoint(x: p.x + CGFloat(cos(a)) * (r + 12), y: p.y + CGFloat(sin(a)) * (r + 12))
                    let s = 3.5 * sin(phase * .pi)
                    g.fill(StarShape.path(center: q, radius: s, points: 4), with: .color(gold.opacity(sin(phase * .pi))))
                }
            }
        case .passed:
            g.stroke(circle(p, r * 0.8), with: .color(Color.gray.opacity(0.55)), style: StrokeStyle(lineWidth: 1.25, dash: [2.5, 3]))
            g.fill(circle(p, 2.5), with: .color(Color.gray.opacity(0.6)))
        }
    }

    private func drawOrbitingComet(_ g: inout GraphicsContext, around p: CGPoint, t: Double, animated: Bool) {
        let rx: CGFloat = 34, ry: CGFloat = 15
        let orbit = Path(ellipseIn: CGRect(x: p.x - rx, y: p.y - ry, width: rx * 2, height: ry * 2))
        g.stroke(orbit, with: .color(Color.white.opacity(0.16)), lineWidth: 1)
        let angle = animated ? t * 1.25 : 0.6
        func at(_ a: Double) -> CGPoint { CGPoint(x: p.x + rx * CGFloat(cos(a)), y: p.y + ry * CGFloat(sin(a))) }
        if animated {
            for i in stride(from: 12, through: 1, by: -1) {
                let f = Double(i) / 12
                g.fill(circle(at(angle - f * 1.1), 3.2 * (1 - f) + 0.6), with: .color(Color.white.opacity(0.5 * (1 - f))))
            }
        }
        drawCometHead(&g, at: at(angle))
    }

    private func drawTravellingComet(_ g: inout GraphicsContext, at cursor: Double, animated: Bool, t: Double) {
        if animated {
            let length = 0.42
            for i in stride(from: 16, through: 1, by: -1) {
                let f = Double(i) / 16
                let q = route.point(max(-1, cursor - f * length))
                g.fill(circle(q, 4 * (1 - f) + 0.5), with: .color(Color(hex: Palette.starlightCyan).opacity(0.55 * (1 - f))))
            }
        }
        let wobble = animated ? CGFloat(sin(t * 3)) * 1.2 : 0
        let p = route.point(cursor)
        drawCometHead(&g, at: CGPoint(x: p.x, y: p.y + wobble))
    }

    private func drawCometHead(_ g: inout GraphicsContext, at p: CGPoint) {
        let cyan = Color(hex: Palette.starlightCyan)
        g.fill(circle(p, 16), with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), cyan.opacity(0.55), cyan.opacity(0)]),
                                                    center: p, startRadius: 0, endRadius: 16))
        g.fill(circle(p, 3.6), with: .color(.white))
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}

/// A small horizontal version of the route for Plan's orbit card: stops
/// along a gentle wave, the travelled part lit, the comet at now.
struct MiniOrbitRoute: View {
    var blocks: [PlanBlock]

    @Environment(AppModel.self) private var app
    @Environment(\.motionLevel) private var motion

    var body: some View {
        if motion.animatesContinuously {
            TimelineView(.animation(minimumInterval: motion.frameInterval(20))) { context in canvas(context.date) }
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in canvas(context.date) }
        }
    }

    private func canvas(_ date: Date) -> some View {
        Canvas { g, size in
            let timeline = DayTimeline(blocks: blocks, now: app.clock.now)
            let n = timeline.blocks.count
            guard n > 0 else { return }
            let animated = motion.animatesContinuously
            let t = date.timeIntervalSinceReferenceDate
            let pad: CGFloat = 10
            func point(_ s: Double) -> CGPoint {
                // s from -0.5 to n - 0.5 spans the width.
                let x = pad + (size.width - pad * 2) * CGFloat((s + 0.5) / Double(n))
                let y = size.height / 2 + CGFloat(sin(.pi * (s + 0.5))) * size.height * 0.22
                return CGPoint(x: x, y: y)
            }
            func path(_ a: Double, _ b: Double) -> Path {
                var p = Path()
                guard b > a else { return p }
                p.move(to: point(a))
                var s = a
                while s < b { s = min(b, s + 0.05); p.addLine(to: point(s)) }
                return p
            }
            let cursor = min(Double(n) - 0.5, max(-0.5, timeline.cursor))
            let violet = Color(hex: Palette.cosmicViolet), gold = Color(hex: Palette.warmGold), cyan = Color(hex: Palette.starlightCyan)
            // The road ahead in the text colour, so it reads at Dawn as well as at night.
            g.stroke(path(cursor, Double(n) - 0.5), with: .color(LMColor.textPrimary.opacity(0.3)),
                     style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1.5, 6], dashPhase: animated ? -t * 8 : 0))
            g.stroke(path(-0.5, cursor), with: .linearGradient(Gradient(colors: [violet, gold]), startPoint: point(-0.5), endPoint: point(cursor)),
                     style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for (k, block) in timeline.blocks.enumerated() {
                let p = point(Double(k))
                let status = timeline.status(of: block)
                let r: CGFloat = 5
                switch status {
                case .upcoming:
                    g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(block.category.color.opacity(0.2)))
                    g.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(block.category.color), lineWidth: 1.25)
                case .active:
                    let pulse = animated ? (t * 0.6).truncatingRemainder(dividingBy: 1) : 0
                    let rr = r + 2 + 9 * pulse
                    g.stroke(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)), with: .color(cyan.opacity(0.6 * (1 - pulse))), lineWidth: 1)
                    g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(cyan))
                case .lit:
                    g.fill(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)),
                           with: .radialGradient(Gradient(colors: [gold.opacity(0.5), gold.opacity(0)]), center: p, startRadius: 0, endRadius: 9))
                    g.fill(StarShape.path(center: p, radius: 6.5, points: max(4, block.category.starPoints)), with: .color(gold))
                case .passed:
                    g.stroke(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(Color.gray.opacity(0.6)), lineWidth: 1)
                }
            }
            if timeline.current == nil {
                let p = point(cursor)
                g.fill(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)),
                       with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), cyan.opacity(0.4), cyan.opacity(0)]), center: p, startRadius: 0, endRadius: 9))
                g.fill(Path(ellipseIn: CGRect(x: p.x - 2.2, y: p.y - 2.2, width: 4.4, height: 4.4)), with: .color(.white))
            }
        }
        .accessibilityHidden(true)
    }
}
