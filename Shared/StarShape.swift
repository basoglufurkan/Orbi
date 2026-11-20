import SwiftUI

/// An n-pointed star (or circle when `points == 0`), used for celestial
/// stars, category chips and widget glyphs.
struct StarShape: Shape {
    var points: Int
    /// Inner radius as a fraction of the outer radius.
    var innerRatio: CGFloat

    init(points: Int, innerRatio: CGFloat? = nil) {
        self.points = points
        self.innerRatio = innerRatio ?? StarShape.defaultInnerRatio(for: points)
    }

    static func defaultInnerRatio(for points: Int) -> CGFloat {
        switch points {
        case 4: 0.32
        case 5: 0.45
        case 6: 0.55
        default: 0.5
        }
    }

    func path(in rect: CGRect) -> Path {
        StarShape.path(center: CGPoint(x: rect.midX, y: rect.midY),
                       radius: min(rect.width, rect.height) / 2,
                       points: points,
                       innerRatio: innerRatio)
    }

    static func path(center: CGPoint, radius: CGFloat, points: Int, innerRatio: CGFloat? = nil) -> Path {
        guard points >= 3 else {
            return Path(ellipseIn: CGRect(x: center.x - radius * 0.62, y: center.y - radius * 0.62,
                                          width: radius * 1.24, height: radius * 1.24))
        }
        let inner = radius * (innerRatio ?? defaultInnerRatio(for: points))
        var path = Path()
        let steps = points * 2
        for i in 0..<steps {
            let angle = (Double(i) / Double(steps)) * 2 * .pi - .pi / 2
            let r = i.isMultiple(of: 2) ? radius : inner
            let p = CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}
