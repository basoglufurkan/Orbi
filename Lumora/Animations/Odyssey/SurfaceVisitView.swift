import SwiftUI

/// In low orbit over a charted world: it rises from the bottom of the
/// screen while its sun crosses the sky. Dawn, day, dusk and night follow each
/// other in a few seconds; the painter turns the world's own night side
/// toward you, so whatever terraforming grew there (rivers, glowing life,
/// city lights, a wonder) shows at its best after dark.
struct SurfaceVisitView: View {
    var world: WorldState
    var onClose: () -> Void

    @Environment(\.motionLevel) private var motion
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date.now
    /// Where in the day the cycle starts: 0 dawn, 0.25 noon, 0.5 dusk, 0.75 midnight.
    @State private var offset = 0.02

    /// One local day, in seconds on screen.
    static let dayLength = 16.0

    enum TimeOfDay: CaseIterable {
        case dawn, day, dusk, night

        var phase: Double {
            switch self {
            case .dawn: 0.02
            case .day: 0.25
            case .dusk: 0.48
            case .night: 0.75
            }
        }

        var title: String {
            switch self {
            case .dawn: String(localized: "Dawn")
            case .day: String(localized: "Daytime")
            case .dusk: String(localized: "Dusk")
            case .night: String(localized: "Night")
            }
        }

        static func at(_ phase: Double) -> TimeOfDay {
            switch phase {
            case ..<0.1: .dawn
            case ..<0.42: .day
            case ..<0.56: .dusk
            case ..<0.94: .night
            default: .dawn
            }
        }
    }

    private var cycles: Bool { motion.animatesContinuously }

    var body: some View {
        let live = cycles && scenePhase == .active
        TimelineView(.animation(minimumInterval: motion.frameInterval(30), paused: !live)) { tl in
            let phase = currentPhase(at: tl.date)
            ZStack {
                Canvas { ctx, size in
                    Self.draw(&ctx, size: size, world: world, phase: phase,
                              time: live ? tl.date.timeIntervalSinceReferenceDate : nil)
                }
                .ignoresSafeArea()
                chrome(phase: phase)
            }
        }
        .background(Color(hex: Palette.deepSpace))
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .onAppear { start = .now }
    }

    private func currentPhase(at date: Date) -> Double {
        guard cycles else { return offset }
        let t = date.timeIntervalSince(start) / Self.dayLength
        return (offset + t).truncatingRemainder(dividingBy: 1)
    }

    // MARK: Chrome

    private func chrome(phase: Double) -> some View {
        let now = TimeOfDay.at(phase)
        return VStack(alignment: .leading, spacing: LMSpace.xs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowText("\(world.blueprint.archetype.displayName) · \(world.stage.title)", color: LMColor.calm)
                    Text(world.blueprint.name)
                        .font(LMFont.voice(.largeTitle)).foregroundStyle(Color(hex: 0xFFF1D6))
                        .accessibilityAddTraits(.isHeader)
                    Text(now.title)
                        .font(LMFont.callout.weight(.semibold)).foregroundStyle(Color(hex: 0xB9BCE3))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.6), value: now)
                }
                Spacer(minLength: 0)
                RoundControlButton(systemImage: "xmark", label: "Back", size: 44) { onClose() }
                    .accessibilityIdentifier("visit.close")
            }
            Spacer()
            Text(WorldLexicon.lore(world.blueprint.archetype, variant: world.blueprint.loreVariant))
                .font(LMFont.voice(.body)).italic()
                .foregroundStyle(Color(hex: 0xFFF1D6).opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.6), radius: 8)
            HStack(spacing: LMSpace.xs) {
                ForEach(TimeOfDay.allCases, id: \.self) { time in
                    Button {
                        start = .now
                        offset = time.phase
                    } label: {
                        Text(time.title)
                            .font(LMFont.footnote.weight(.semibold))
                            .foregroundStyle(time == now ? Color(hex: Palette.deepSpace) : Color(hex: 0xFFF1D6))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(time == now ? Color(hex: 0xFFF1D6) : Color.white.opacity(0.12)))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("visit.\(time)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Time of day"))
        }
        .padding(.horizontal, LMSpace.l)
        .padding(.top, LMSpace.m)
        .padding(.bottom, LMSpace.l)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    // MARK: Drawing

    /// `phase` 0…1 is one local day: the sun rises on the left at 0, stands
    /// overhead at 0.25, sets on the right at 0.5 and is below you until 1.
    nonisolated static func draw(_ ctx: inout GraphicsContext, size: CGSize, world: WorldState, phase: Double, time: Double?) {
        let w = size.width, h = size.height
        let horizonY = h * 0.5
        let sunAngle = phase * 2 * .pi
        // Height of the sun above the horizon, -1…1, and how much daylight that makes.
        let elevation = sin(sunAngle)
        let daylight = max(0, min(1, (elevation + 0.12) / 0.5))
        let twilight = max(0, 1 - abs(elevation) / 0.28)
        let palette = world.blueprint.palette

        // Sky: deep space at night, the world's own air by day, warm at the edges of the day.
        let night = Color(hex: Palette.deepSpace)
        let air = Color(hex: palette.atmosphere)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(night))
        if daylight > 0 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizonY + 40)),
                     with: .linearGradient(Gradient(colors: [air.opacity(0.06 * daylight), air.opacity(0.38 * daylight)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: horizonY)))
        }
        // Stars come out as the light goes.
        StarFieldPainter.draw(&ctx, size: size, opacity: 0.95 * (1 - daylight), time: time)

        // The sun on its arc, and the glow it throws along the horizon.
        let sun = CGPoint(x: w / 2 - cos(sunAngle) * w * 0.58, y: horizonY - elevation * h * 0.42)
        if elevation > -0.2 {
            var glow = ctx
            glow.blendMode = .plusLighter
            CelestialPainter.glow(&glow, at: CGPoint(x: sun.x, y: max(sun.y, horizonY - 20)), radius: w * (0.5 + 0.6 * twilight),
                                  color: Color(hex: twilight > 0.3 ? Palette.warmGold : palette.highlight),
                                  intensity: 0.35 * max(daylight, twilight))
            if elevation > -0.05 {
                CelestialPainter.star(&glow, at: sun, radius: 20, points: 4, color: Color(hex: 0xFFF1D6),
                                      brightness: 1.2, flare: true)
            }
        }

        // Moons climb the sky at night.
        if world.blueprint.moonCount > 0, elevation < 0.1 {
            for i in 0..<min(2, world.blueprint.moonCount) {
                let a = sunAngle + .pi + Double(i) * 0.7
                let p = CGPoint(x: w / 2 - cos(a) * w * 0.5, y: horizonY - sin(a) * h * (0.32 - 0.08 * Double(i)))
                guard p.y < horizonY - 10 else { continue }
                var moon = ctx
                moon.opacity = 1 - daylight
                CelestialPainter.moon(&moon, at: p, radius: 14 - CGFloat(i) * 4)
            }
        }

        // The world beneath you, lit from wherever the sun is now. Drawn at
        // the proportions it was painted for, so its features stay crisp.
        var bp = world.blueprint
        bp.lightAngle = .pi + sunAngle
        let radius = min(w * 0.78, h * 0.42)
        WorldPainter.draw(&ctx, world: bp, center: CGPoint(x: w / 2, y: horizonY + radius * 0.92), radius: radius,
                          stage: world.stage, time: time)

        // A soft floor so the lore and controls stay readable.
        ctx.fill(Path(CGRect(x: 0, y: h * 0.72, width: w, height: h * 0.28)),
                 with: .linearGradient(Gradient(colors: [night.opacity(0), night.opacity(0.75)]),
                                       startPoint: CGPoint(x: 0, y: h * 0.72), endPoint: CGPoint(x: 0, y: h)))
    }
}
