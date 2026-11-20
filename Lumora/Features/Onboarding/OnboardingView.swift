import AuthenticationServices
import SwiftUI

/// Three cinematic chapters with Pell as the guide, then Pell's invitation
/// to light the first star. No sign-up wall: Sign in with Apple is offered
/// beside starting without an account, and either works offline; skippable
/// after chapter one.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.motionLevel) private var motion
    @State private var chapter = 0
    @State private var name = ""
    @State private var showAlreadyHave = false
    @State private var firstMinutes = 25
    @FocusState private var nameFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack {
            CosmicBackgroundView(mood: .home, light: 0.2 + Double(chapter) * 0.2, starOpacity: 0.5 + Double(chapter) * 0.25)
            OnboardingSceneView(chapter: chapter)
                .ignoresSafeArea()
                // Large copy runs over the art, so it steps back.
                .opacity(nameFocused ? 0.18 : (typeSize.isAccessibilitySize ? 0.45 : 1))
                .animation(LMSpring.settle, value: nameFocused)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: LMSpace.m) {
                HStack {
                    Spacer()
                    if chapter < Self.accountChapter {
                        Button(String(localized: "Skip")) {
                            app.haptics.selection()
                            advance(to: Self.accountChapter)
                        }
                        .font(LMFont.headline)
                        .foregroundStyle(LMColor.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("onboarding.skip")
                    }
                }
                // The copy sits low above the controls and scrolls at large
                // text sizes; Skip and the controls always stay on screen.
                FittingScrollView(alignment: .bottomLeading) {
                    chapterText
                        .id(chapter)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: motion == .reduced ? 0 : 18)),
                                                removal: .opacity))
                }
                Group {
                    switch chapter {
                    case Self.accountChapter: accountActions
                    case Self.firstStarChapter: firstStarActions
                    default: pager
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, LMSpace.l)
            .readableColumn()
            .padding(.bottom, LMSpace.m)
        }
        .alert(String(localized: "Your universe follows you"), isPresented: $showAlreadyHave) {
            Button(String(localized: "Continue")) { finish(startingFocus: false) }
        } message: {
            Text("If iCloud sync was on, your universe comes back on its own once you're signed in to the same iCloud account. It can take a few minutes; your sky is redrawn star by star.")
        }
        .telemetryScreen("onboarding")
        .onAppear { if chapter == 0 { Telemetry.log(.onboardingStarted) } }
        .onChange(of: chapter) { _, now in
            let step = switch now {
            case Self.accountChapter: "account"
            case Self.firstStarChapter: "first_star"
            default: "chapter_\(now + 1)"
            }
            Telemetry.log(.onboardingStep(step: step))
        }
    }

    private var chapterText: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(eyebrow, color: LMColor.calm)
            Text(title)
                .font(LMFont.voice(.largeTitle))
                .foregroundStyle(LMColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(bodyText)
                .font(LMFont.body)
                .foregroundStyle(LMColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pager: some View {
        HStack {
            HStack(spacing: 8) {
                ForEach(0...Self.accountChapter, id: \.self) { i in
                    Capsule()
                        .fill(i == chapter ? LMColor.textPrimary : LMColor.textTertiary.opacity(0.6))
                        .frame(width: i == chapter ? 34 : 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Chapter \(chapter + 1) of 3"))
            Spacer()
            Button {
                app.haptics.selection()
                advance(to: chapter + 1)
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LMColor.starlightLabel)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(LMColor.starlightFill))
                    .background(Circle().stroke(LMColor.focus.opacity(0.25), lineWidth: 8).padding(-8))
                    .shadow(color: LMColor.focus.opacity(0.5), radius: 20)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(Text("Next chapter"))
            .accessibilityIdentifier("onboarding.next")
        }
    }

    private var accountActions: some View {
        VStack(spacing: LMSpace.s) {
            // At accessibility sizes the long prompt becomes a visible label,
            // since a placeholder can't wrap and would shrink instead.
            if typeSize.isAccessibilitySize {
                Text("What should your universe call you?")
                    .font(LMFont.callout)
                    .foregroundStyle(LMColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            TextField(typeSize.isAccessibilitySize ? String(localized: "Name (optional)")
                                                   : String(localized: "What should your universe call you? (optional)"),
                      text: $name)
                .font(LMFont.body)
                .foregroundStyle(LMColor.textPrimary)
                .focused($nameFocused)
                .submitLabel(.done)
                .textContentType(.givenName)
                .accessibilityLabel(Text("What should your universe call you? Optional"))
                .padding(.horizontal, 20)
                .frame(minHeight: 52)
                .glassCard(radius: 20)
                .accessibilityIdentifier("onboarding.name")
            SignInWithAppleButton(.continue) { request in
                AppleAccount.configure(request)
            } onCompletion: { result in
                if case let .success(given) = app.account.complete(result) {
                    if name.trimmingCharacters(in: .whitespaces).isEmpty, let given { name = given }
                    chooseAccount()
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 56)
            .clipShape(Capsule())
            .accessibilityIdentifier("onboarding.apple")
            CosmicButton(title: "Start without an account", systemImage: "sparkle", kind: .secondary) { chooseAccount() }
                .accessibilityIdentifier("onboarding.create")
            Button(String(localized: "I already have a universe")) { showAlreadyHave = true }
                .font(LMFont.headline.weight(.medium))
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
        }
    }

    /// Pell's invitation: a length for the first session, then straight in.
    private var firstStarActions: some View {
        VStack(spacing: LMSpace.s) {
            HStack(spacing: LMSpace.s) {
                ForEach([10, 25, 45], id: \.self) { m in
                    Button {
                        app.haptics.selection()
                        withAnimation(LMSpring.snap) { firstMinutes = m }
                    } label: {
                        Text(String(localized: "\(m) min"))
                            .font(LMFont.headline)
                            .foregroundStyle(firstMinutes == m ? LMColor.starlightLabel : LMColor.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Capsule().fill(firstMinutes == m ? LMColor.starlightFill : LMColor.textPrimary.opacity(0.08)))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityAddTraits(firstMinutes == m ? .isSelected : [])
                }
            }
            CosmicButton(title: "Light my first star", systemImage: "sparkle", kind: .reward) { finish(startingFocus: true) }
                .accessibilityIdentifier("onboarding.firstStar")
            Button(String(localized: "Later")) { finish(startingFocus: false) }
                .font(LMFont.headline.weight(.medium))
                .foregroundStyle(LMColor.textSecondary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("onboarding.later")
        }
    }

    static let accountChapter = 2
    static let firstStarChapter = 3

    private func chooseAccount() {
        nameFocused = false
        app.haptics.selection()
        advance(to: Self.firstStarChapter)
    }

    private func advance(to next: Int) {
        let target = min(Self.firstStarChapter, next)
        if motion == .reduced {
            withAnimation(.easeInOut(duration: 0.4)) { chapter = target }
        } else {
            withAnimation(LMCurve.emerge.animation(duration: 1.2)) { chapter = target }
        }
    }

    private func finish(startingFocus: Bool) {
        nameFocused = false
        app.haptics.sessionStart()
        app.completeOnboarding(name: name)
        app.queueIntroOffer()
        Telemetry.log(.onboardingCompleted(nameGiven: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                                           appleSignIn: app.account.isSignedIn))
        guard startingFocus else { return }
        app.focusSource = "onboarding"
        app.timer.start(FocusConfiguration(plannedSeconds: firstMinutes * 60, category: app.preferences.lastCategory,
                                           intention: "", taskID: nil))
    }

    private var eyebrow: String {
        switch chapter {
        case 0: String(localized: "Chapter one · First light")
        case 1: String(localized: "Chapter two · Connection")
        case 2: String(localized: "Chapter three · Your world")
        default: String(localized: "Your first star")
        }
    }

    private var title: String {
        switch chapter {
        case 0: String(localized: "Focus, and a star is born.")
        case 1: String(localized: "Your days turn into constellations.")
        case 2: String(localized: "Ten sessions, and your first planet.")
        default: String(localized: "Shall we light your first star?")
        }
    }

    private var bodyText: String {
        switch chapter {
        case 0: String(localized: "Orbi is a focus timer: every session you finish lights a star in a sky that's yours alone. I'm Pell, and I'll keep you company.")
        case 1: String(localized: "One session, one star. Four in a day, and they reach for each other. Breaks are for resting with me.")
        case 2: String(localized: "Nothing you build here ever fades — missed days only rest. Keep your sky with Apple, or start right away.")
        default: String(localized: "Pick a length. I'll be right here until it's done.")
        }
    }
}

/// Procedural scenes for the three chapters, crossfading between them.
private struct OnboardingSceneView: View {
    var chapter: Int
    @Environment(\.motionLevel) private var motion
    @Environment(\.scenePhase) private var scenePhase
    @State private var chapterStart = Date.now

    var body: some View {
        let animate = motion.animatesContinuously && scenePhase == .active
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: motion.frameInterval(30), paused: !animate)) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSince(chapterStart)
                    let wall = tl.date.timeIntervalSinceReferenceDate
                    // Short screens (iPhone SE) draw the scene smaller and higher so
                    // it clears the chapter copy.
                    let k = min(1, size.height / 844)
                    // The account chapter carries the most copy, so its scene sits higher.
                    let high = chapter >= 2
                    let c = CGPoint(x: size.width / 2, y: size.height * (k < 0.9 ? (high ? 0.2 : 0.3) : (high ? 0.24 : 0.36)))
                    let blink = animate ? PellFace.blink(at: wall) : 0
                    let bob = animate ? sin(wall * 2 * .pi / 5) * 3 * k : 0
                    let pellIn = animate ? LMCurve.emerge.value((t - 0.5) / 0.9) : 1
                    /// Pell, the guide, beside each scene.
                    func pell(_ ctx: inout GraphicsContext, _ at: CGPoint, _ r: CGFloat, _ face: PellExpression) {
                        guard pellIn > 0 else { return }
                        var pc = ctx
                        pc.blendMode = .normal
                        pc.opacity = pellIn
                        PellPainter.draw(&pc, center: CGPoint(x: at.x, y: at.y + bob + (1 - pellIn) * 14),
                                         radius: r, expression: face, blink: face.hasOpenEyes ? blink : 0)
                    }
                    ctx.blendMode = .plusLighter
                    switch chapter {
                    case 0:
                        let breath = animate ? 1 + 0.06 * sin(wall * 2 * .pi / 4) : 1
                        CelestialPainter.glow(&ctx, at: c, radius: 180 * k, color: Color(hex: Palette.cosmicViolet), intensity: 0.45)
                        CelestialPainter.star(&ctx, at: c, radius: 26 * k * breath, points: 4, color: Color(hex: Palette.warmGold), brightness: 1.2)
                        pell(&ctx, CGPoint(x: c.x + 105 * k, y: c.y + 110 * k), 30 * k, .curious)
                    case 1:
                        let pts = [CGPoint(x: c.x - 110 * k, y: c.y + 60 * k), CGPoint(x: c.x - 40 * k, y: c.y - 30 * k),
                                   CGPoint(x: c.x + 40 * k, y: c.y + 10 * k), CGPoint(x: c.x + 110 * k, y: c.y - 70 * k)]
                        let colors = FocusCategory.allCases.map(\.color)
                        let draw = animate ? min(1, max(0, (t - 0.4) / 1.6)) : 1
                        var path = Path()
                        path.move(to: pts[0])
                        let segments = Double(pts.count - 1)
                        for i in 1..<pts.count {
                            let local = min(1, max(0, draw * segments - Double(i - 1)))
                            guard local > 0 else { break }
                            path.addLine(to: lerp(pts[i - 1], pts[i], local))
                        }
                        ctx.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 1.2)
                        for (i, p) in pts.enumerated() {
                            let appear = animate ? min(1, max(0, (t - Double(i) * 0.25) / 0.5)) : 1
                            CelestialPainter.star(&ctx, at: p, radius: 12 * CGFloat(bloomSpring(appear)),
                                                  points: FocusCategory.allCases[i].starPoints, color: colors[i], brightness: 1)
                        }
                        pell(&ctx, CGPoint(x: c.x + 80 * k, y: c.y + 110 * k), 28 * k, .happy)
                    case 2:
                        let grow = animate ? LMCurve.emerge.value(min(1, t / 1.6)) : 1
                        var pc = ctx
                        pc.blendMode = .normal
                        CelestialPainter.planet(&pc, at: c, radius: 70 * k * CGFloat(grow), palette: .named("rose"),
                                                ringOpacity: grow, light: 1)
                        CelestialPainter.star(&ctx, at: CGPoint(x: c.x - 120 * k, y: c.y - 90 * k), radius: 8, points: 4,
                                              color: Color(hex: Palette.warmGold), brightness: 0.9)
                        pell(&ctx, CGPoint(x: c.x + 115 * k, y: c.y - 85 * k), 24 * k, .proud)
                    default:
                        // Pell waits beside an unlit star: the first one, about to be made.
                        let breath = animate ? 0.5 + 0.5 * sin(wall * 2 * .pi / 3) : 1
                        CelestialPainter.glow(&ctx, at: c, radius: 200 * k, color: Color(hex: Palette.cosmicViolet), intensity: 0.35)
                        CelestialPainter.star(&ctx, at: CGPoint(x: c.x + 70 * k, y: c.y - 55 * k), radius: (6 + 4 * breath) * k,
                                              points: 4, color: Color(hex: Palette.warmGold), brightness: 0.5 + 0.4 * breath)
                        pell(&ctx, CGPoint(x: c.x - 15 * k, y: c.y + 15 * k), 48 * k, .calm)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onChange(of: chapter) { _, _ in chapterStart = .now }
        .accessibilityHidden(true)
    }
}
