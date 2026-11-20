import SwiftUI

/// The shared focus room while focusing together: a slowly turning galaxy,
/// and everyone in the room as an astronaut at their own desk inside it.
/// People appear when they join and drift away when they finish or leave.
/// RealityKit draws it in 3D on iOS 18 and later; iOS 17 gets a flat drawing.
struct TogetherGalaxyView: View {
    var people: [Person]
    var category: FocusCategory

    @Environment(\.motionLevel) private var motion

    /// One seat in the room.
    struct Person: Identifiable, Equatable {
        var id: Int
        var name: String
        var isMe: Bool
        var isHost: Bool

        /// Each seat keeps its own colour, so people are easy to tell apart.
        var hex: UInt32 { Self.hues[id % Self.hues.count] }
        static let hues: [UInt32] = [Palette.warmGold, Palette.cosmicViolet, Palette.starlightCyan, Palette.nebulaPink,
                                     0x9CF2C0, 0xFFB07A, 0xC9B8FF, 0x7FD4FF]
    }

    var body: some View {
        // The band between the header and the timer.
        GeometryReader { proxy in
            Group {
                if #available(iOS 18.0, *), !Self.forceFlat {
                    TogetherGalaxy3D(people: people, category: category, animates: motion.animatesContinuously)
                } else {
                    TogetherGalaxy2D(people: people, category: category, animates: motion.animatesContinuously)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height * Self.band.height)
            .offset(y: proxy.size.height * Self.band.top)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityIdentifier("together.galaxy")
    }

    /// DEBUG: `-lumora-together-2d` shows the iOS 17 drawing on newer systems.
    #if DEBUG
    static let forceFlat = ProcessInfo.processInfo.arguments.contains("-lumora-together-2d")
    #else
    static let forceFlat = false
    #endif

    /// Top and height of the scene, as fractions of the screen.
    static let band = (top: 0.11, height: 0.5)

    private var accessibilityText: String {
        let names = people.map { $0.isMe ? String(localized: "you") : $0.name }
        return String(localized: "Focusing together: \(names.formatted(.list(type: .and)))")
    }
}

/// Where each seat sits, shared by both renderers, in scene units (a desk's
/// platform is about 0.55 across). Narrow screens hold three to a row, wide
/// ones four; more people fill a second row behind.
enum TogetherGalaxyLayout {
    struct Seat: Equatable {
        /// Left (−) to right (+), centred on 0.
        var x: Double
        /// 0 for the front row, 1 for the back row.
        var row: Int
    }

    /// Centre-to-centre distance between neighbouring desks.
    static let step = 0.72

    static func seats(count: Int, perRow: Int) -> [Seat] {
        guard count > 0 else { return [] }
        let front = count <= perRow ? count : Int((Double(count) / 2).rounded(.up))
        let back = count - front
        func row(_ n: Int, _ index: Int) -> [Seat] {
            (0..<n).map { Seat(x: (Double($0) - Double(n - 1) / 2) * step, row: index) }
        }
        return row(back, 1) + row(front, 0)
    }

    static func perRow(aspect: Double) -> Int { aspect < 1.25 ? 3 : 4 }

    /// How far the widest row reaches from the centre, desk included.
    static func halfWidth(_ seats: [Seat]) -> Double {
        (seats.map { abs($0.x) }.max() ?? 0) + 0.42
    }
}

// MARK: - iOS 17

/// The flat version: a drawn spiral galaxy and a little astronaut per seat.
struct TogetherGalaxy2D: View {
    var people: [TogetherGalaxyView.Person]
    var category: FocusCategory
    var animates: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height * 0.5)
            TimelineView(.animation(minimumInterval: 1 / 24, paused: !animates)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    Canvas { context, _ in
                        Self.drawGalaxy(in: &context, center: center, radius: size.width * 0.5, t: t)
                    }
                    let seats = TogetherGalaxyLayout.seats(count: people.count,
                                                           perRow: TogetherGalaxyLayout.perRow(aspect: size.width / max(1, size.height)))
                    // Scene units to points, so the widest row fills the width.
                    let unit = min(size.width / 2 / TogetherGalaxyLayout.halfWidth(seats), 150)
                    ForEach(Array(zip(people, seats)), id: \.0.id) { person, seat in
                        AstronautBadge(person: person, bob: animates ? sin(t * 0.9 + Double(person.id)) * 3 : 0)
                            .scaleEffect(seat.row == 1 ? 0.82 : 1)
                            .position(x: center.x + seat.x * unit,
                                      y: center.y + (seat.row == 1 ? 0 : unit * 0.62))
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .animation(LMSpring.settle, value: people.map(\.id))
            }
        }
    }

    private static func drawGalaxy(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, t: Double) {
        CelestialPainter.glow(&context, at: center, radius: radius * 0.55, color: Color(hex: Palette.cosmicViolet), intensity: 0.35)
        CelestialPainter.glow(&context, at: center, radius: radius * 0.18, color: Color(hex: Palette.warmGold), intensity: 0.8)
        var rng = SeededRandom(seed: 7)
        let turn = t * 0.04
        for i in 0..<320 {
            let arm = Double(i % 2) * .pi
            let d = pow(rng.unit(), 0.7)
            let angle = arm + d * 5.2 + turn + rng.range(-0.35, 0.35)
            let r = radius * (0.08 + d * 0.92)
            // Flattened, as a disc seen at an angle.
            let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r * 0.38)
            let s = rng.range(0.8, 2.2)
            let hue = [Palette.softWhite, Palette.cosmicViolet, Palette.nebulaPink, Palette.warmGold][i % 4]
            context.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s, width: s * 2, height: s * 2)),
                         with: .color(Color(hex: hue).opacity(0.35 + 0.6 * (1 - d))))
        }
    }
}

/// A seated astronaut at a desk with a glowing laptop, drawn with shapes.
private struct AstronautBadge: View {
    var person: TogetherGalaxyView.Person
    var bob: Double

    var body: some View {
        let accent = Color(hex: person.hex)
        VStack(spacing: 4) {
            ZStack {
                // Helmet and visor.
                Circle().fill(Color(hex: Palette.softWhite)).frame(width: 34, height: 34).offset(y: -26)
                Capsule().fill(LinearGradient(colors: [Color(hex: Palette.midnightIndigo), accent.opacity(0.7)],
                                              startPoint: .top, endPoint: .bottom))
                    .frame(width: 24, height: 15).offset(y: -27)
                // Suit.
                RoundedRectangle(cornerRadius: 10).fill(Color(hex: Palette.softWhite).opacity(0.92))
                    .frame(width: 40, height: 30).offset(y: 2)
                // Desk and laptop.
                RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.85)).frame(width: 22, height: 15).offset(y: 6)
                    .shadow(color: accent.opacity(0.8), radius: 6)
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: Palette.midnightIndigo))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(accent.opacity(0.6), lineWidth: 1))
                    .frame(width: 76, height: 8).offset(y: 17)
            }
            .frame(width: 80, height: 76)
            .offset(y: bob)
            Text(person.isMe ? String(localized: "You") : person.name)
                .font(LMFont.footnote.weight(.semibold))
                .foregroundStyle(person.isMe ? LMColor.reward : LMColor.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 90)
        }
    }
}
