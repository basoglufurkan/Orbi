import SwiftUI

/// Motion language (Motion & handoff, p.26).
enum LMSpring {
    /// Button press, chips, toggles.
    static let snap = Animation.spring(response: 0.30, dampingFraction: 0.90)
    /// Sheets, tab morph, star placement, summary.
    static let settle = Animation.spring(response: 0.45, dampingFraction: 0.85)
    /// Star birth, duration orb, card flip.
    static let bloom = Animation.spring(response: 0.55, dampingFraction: 0.72)
    /// Parallax follow, explorer pan inertia.
    static let drift = Animation.spring(response: 0.90, dampingFraction: 1.0)
}

/// Named cubic-bezier curves, usable both as SwiftUI animations and as pure
/// easing functions for timeline-driven rendering.
enum LMCurve {
    case drift, emerge, anticipate, release, easeOutCubic, easeInOutCubic, easeOutExpo, easeOutQuad

    var unitCurve: UnitCurve {
        switch self {
        case .drift: .bezier(startControlPoint: UnitPoint(x: 0.45, y: 0), endControlPoint: UnitPoint(x: 0.55, y: 1))
        case .emerge: .bezier(startControlPoint: UnitPoint(x: 0.22, y: 1), endControlPoint: UnitPoint(x: 0.36, y: 1))
        case .anticipate: .bezier(startControlPoint: UnitPoint(x: 0.36, y: 0), endControlPoint: UnitPoint(x: 0.66, y: -0.56))
        case .release: .bezier(startControlPoint: UnitPoint(x: 0.16, y: 1), endControlPoint: UnitPoint(x: 0.3, y: 1))
        case .easeOutCubic: .bezier(startControlPoint: UnitPoint(x: 0.33, y: 1), endControlPoint: UnitPoint(x: 0.68, y: 1))
        case .easeInOutCubic: .bezier(startControlPoint: UnitPoint(x: 0.65, y: 0), endControlPoint: UnitPoint(x: 0.35, y: 1))
        case .easeOutExpo: .bezier(startControlPoint: UnitPoint(x: 0.16, y: 1), endControlPoint: UnitPoint(x: 0.3, y: 1))
        case .easeOutQuad: .bezier(startControlPoint: UnitPoint(x: 0.5, y: 1), endControlPoint: UnitPoint(x: 0.89, y: 1))
        }
    }

    /// Eased value for linear progress `t` (clamped to 0...1).
    func value(_ t: Double) -> Double {
        unitCurve.value(at: min(1, max(0, t)))
    }

    func animation(duration: Double) -> Animation {
        .timingCurve(unitCurve, duration: duration)
    }
}

enum LMSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let hero: CGFloat = 72
    /// Widest a column of cards and text gets (iPad, large windows).
    static let readableWidth: CGFloat = 720
}

extension View {
    /// Keeps a content column at a readable width, centered, on wide screens.
    /// No effect on iPhone, where screens are narrower than the cap.
    func readableColumn(_ width: CGFloat = LMSpace.readableWidth) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}

enum LMRadius {
    static let chip: CGFloat = 12
    static let row: CGFloat = 20
    static let card: CGFloat = 28
}
