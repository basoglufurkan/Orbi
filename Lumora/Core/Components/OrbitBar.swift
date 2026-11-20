import SwiftUI

/// Floating orbit bar (Navigation): 64pt glass capsule; the selected tab
/// expands into a labelled capsule with a matched-geometry morph.
struct OrbitBar: View {
    @Binding var selection: AppTab
    @Namespace private var ns
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let selected = tab == selection
                Button {
                    guard tab != selection else { return }
                    app.haptics.selection()
                    withAnimation(LMSpring.settle) { selection = tab }
                } label: {
                    HStack(spacing: 8) {
                        TabGlyph(tab: tab)
                        if selected {
                            Text(tab.title).font(LMFont.headline).lineLimit(1).fixedSize()
                        }
                    }
                    .foregroundStyle(selected ? LMColor.textPrimary : LMColor.textTertiary)
                    .padding(.horizontal, selected ? 18 : 0)
                    .frame(maxWidth: selected ? nil : .infinity, minHeight: 46)
                    .background {
                        if selected {
                            Capsule().fill(LMColor.textPrimary.opacity(0.1))
                                .matchedGeometryEffect(id: "orbit.selection", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
                // Like the system tab bar: the bar keeps its size and a long
                // press shows the Large Content Viewer at accessibility sizes.
                .accessibilityShowsLargeContentViewer {
                    TabGlyph(tab: tab)
                    Text(tab.title)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .padding(7)
        .frame(height: 62)
        .glassCard(radius: 31)
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }
}

/// Tab icons: SF Symbols where a match exists, a drawn ringed planet for Universe.
struct TabGlyph: View {
    var tab: AppTab

    var body: some View {
        if tab == .universe {
            PlanetRingGlyph()
                .stroke(style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
                .frame(width: 22, height: 22)
        } else if tab == .odyssey {
            RocketGlyph()
                .stroke(style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: tab.symbol).font(.system(size: 18, weight: .medium))
        }
    }
}

/// A small ringed planet on a 24pt grid, 1.75 stroke (Foundations · Icons).
struct PlanetRingGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) * 0.26
        path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let ring = Path(ellipseIn: CGRect(x: -rect.width * 0.48, y: -rect.height * 0.16, width: rect.width * 0.96, height: rect.height * 0.32))
            .applying(CGAffineTransform(rotationAngle: -0.4).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
        path.addPath(ring)
        return path
    }
}

/// A small rocket on a 24pt grid, 1.75 stroke, tilted toward the stars.
struct RocketGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Body: nose at top, rounded flanks.
        p.move(to: CGPoint(x: 0.5 * w, y: 0.06 * h))
        p.addQuadCurve(to: CGPoint(x: 0.68 * w, y: 0.66 * h), control: CGPoint(x: 0.78 * w, y: 0.3 * h))
        p.addLine(to: CGPoint(x: 0.32 * w, y: 0.66 * h))
        p.addQuadCurve(to: CGPoint(x: 0.5 * w, y: 0.06 * h), control: CGPoint(x: 0.22 * w, y: 0.3 * h))
        // Fins.
        p.move(to: CGPoint(x: 0.33 * w, y: 0.5 * h))
        p.addLine(to: CGPoint(x: 0.18 * w, y: 0.74 * h))
        p.addLine(to: CGPoint(x: 0.33 * w, y: 0.68 * h))
        p.move(to: CGPoint(x: 0.67 * w, y: 0.5 * h))
        p.addLine(to: CGPoint(x: 0.82 * w, y: 0.74 * h))
        p.addLine(to: CGPoint(x: 0.67 * w, y: 0.68 * h))
        // Porthole and flame.
        p.addEllipse(in: CGRect(x: 0.43 * w, y: 0.3 * h, width: 0.14 * w, height: 0.14 * w))
        p.move(to: CGPoint(x: 0.42 * w, y: 0.76 * h))
        p.addQuadCurve(to: CGPoint(x: 0.58 * w, y: 0.76 * h), control: CGPoint(x: 0.5 * w, y: 1.02 * h))
        return p.applying(CGAffineTransform(translationX: -rect.midX, y: -rect.midY)
            .concatenating(CGAffineTransform(rotationAngle: .pi / 4))
            .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY)))
    }
}
