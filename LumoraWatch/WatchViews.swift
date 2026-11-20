import SwiftUI
import WatchKit

/// Today's light and a quick start.
struct WatchHomeView: View {
    @Environment(WatchSession.self) private var session

    var body: some View {
        let s = session.state
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: s.goalMinutes > 0 ? min(1, Double(s.todayMinutes) / Double(s.goalMinutes)) : 0)
                        .stroke(WatchStyle.violet, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Image(systemName: "sparkle").foregroundStyle(WatchStyle.gold)
                        Text("\(s.todayMinutes)").font(.system(.title3, design: .rounded).weight(.semibold))
                        Text("of \(s.goalMinutes) min").font(.caption2).foregroundStyle(WatchStyle.secondary)
                    }
                }
                .frame(width: 96, height: 96)
                .accessibilityElement(children: .combine)

                Button {
                    session.start(minutes: s.defaultMinutes)
                } label: {
                    Label("Focus \(s.defaultMinutes) min", systemImage: "sparkle")
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchStyle.violet)
                .buttonStyle(.borderedProminent)

                HStack {
                    ForEach([15, 45].filter { $0 != s.defaultMinutes }, id: \.self) { minutes in
                        Button("\(minutes) min") { session.start(minutes: minutes) }
                            .buttonStyle(.bordered)
                    }
                }

                if s.stars > 0 {
                    Text(s.stars == 1 ? "1 star in your universe" : "\(s.stars) stars in your universe")
                        .font(.caption2).foregroundStyle(WatchStyle.secondary)
                }
                if session.unreachable {
                    Text("Open Orbi on your iPhone to start.")
                        .font(.caption2).foregroundStyle(WatchStyle.gold).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Orbi")
        .containerBackground(WatchStyle.space.gradient, for: .navigation)
    }
}

/// The running session: a ring that fills as your light gathers.
struct WatchFocusView: View {
    @Environment(WatchSession.self) private var session

    var body: some View {
        let s = session.state
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            let remaining = s.remaining(at: now)
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: s.progress(at: now))
                        .stroke(WatchStyle.violet, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        if !s.category.isEmpty {
                            Text(verbatim: s.category).textCase(.uppercase).font(.system(size: 10, weight: .bold)).foregroundStyle(WatchStyle.cyan)
                        }
                        Text(Self.clock(remaining))
                            .font(.system(size: 34, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WatchStyle.text.opacity(s.phase == .paused ? 0.55 : 1))
                        if s.phase == .paused {
                            Text("Paused").font(.caption2).foregroundStyle(WatchStyle.secondary)
                        }
                    }
                }
                .padding(.horizontal, 6)
                HStack(spacing: 10) {
                    Button { session.end() } label: { Image(systemName: "stop.fill") }
                        .tint(.white.opacity(0.25))
                        .accessibilityLabel(Text("End session"))
                    Button {
                        s.phase == .paused ? session.resume() : session.pause()
                    } label: {
                        Image(systemName: s.phase == .paused ? "play.fill" : "pause.fill")
                    }
                    .tint(WatchStyle.violet)
                    .accessibilityLabel(s.phase == .paused ? Text("Resume") : Text("Pause"))
                }
                .buttonStyle(.borderedProminent)
            }
            .onChange(of: now) { _, date in session.tick(at: date) }
        }
        .containerBackground(WatchStyle.space.gradient, for: .navigation)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A new star is born on your wrist: it gathers, flares, and settles.
struct StarBirthView: View {
    var onDone: () -> Void
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height * 0.42)
                // Specks of light fall inward, then the star flares and settles.
                let gather = min(1, t / 1.2)
                for i in 0..<14 {
                    let a = Double(i) * 2.39996
                    let d = (1 - gather) * Double(min(size.width, size.height)) * (0.35 + 0.25 * Double(i % 3) / 2)
                    let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)),
                             with: .color(WatchStyle.gold.opacity(1 - gather * 0.7)))
                }
                let flare = t < 1.2 ? 0 : min(1, (t - 1.2) / 0.4)
                let settle = t < 1.6 ? 1 : max(0.65, 1 - (t - 1.6) * 0.3)
                let r = 22 * flare * settle
                if r > 0 {
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 2.4, y: c.y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                             with: .radialGradient(Gradient(colors: [WatchStyle.gold.opacity(0.55), .clear]),
                                                   center: c, startRadius: 0, endRadius: r * 2.4))
                    var star = Path()
                    for k in 0..<8 {
                        let angle = Double(k) * .pi / 4 - .pi / 2
                        let rr = k.isMultiple(of: 2) ? r : r * 0.32
                        let q = CGPoint(x: c.x + cos(angle) * rr, y: c.y + sin(angle) * rr)
                        k == 0 ? star.move(to: q) : star.addLine(to: q)
                    }
                    star.closeSubpath()
                    ctx.fill(star, with: .color(Color(red: 1, green: 0.97, blue: 0.88)))
                }
            }
            .overlay(alignment: .bottom) {
                if t > 1.8 {
                    VStack(spacing: 2) {
                        Text("A new star").font(.headline).foregroundStyle(WatchStyle.text)
                        Text("Your light is in the sky.").font(.caption2).foregroundStyle(WatchStyle.secondary)
                    }
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
            }
            .onChange(of: t > 4.5) { _, done in if done { onDone() } }
        }
        .background(WatchStyle.space)
        .onTapGesture { onDone() }
    }
}
