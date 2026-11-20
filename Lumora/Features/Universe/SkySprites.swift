import SwiftUI
import UIKit

/// Bitmaps of the sky's expensive objects — galaxies, worlds, stars, nebulae
/// and labels — so panning and zooming only move pictures around instead of
/// redrawing thousands of gradients and retypesetting text every frame.
///
/// Each object is rendered at a few radius steps (×1.25 apart) and drawn
/// scaled to the exact size. A frame never renders: it asks for what it
/// needs, draws the vector original for anything not ready yet, and the
/// missing bitmaps are made between frames, a few milliseconds at a time.
/// Used only on the main thread (from a live sky's canvas), hence unchecked.
@Observable
final class SkySprites: @unchecked Sendable {
    static let shared = SkySprites()

    /// Bumped when new bitmaps are ready, so a paused sky redraws with them.
    private(set) var generation = 0

    struct Request {
        var item: String
        var bucket: Int
        var radius: CGFloat
        /// Bitmap side as a multiple of the radius.
        var extent: CGFloat
        var scale: CGFloat
        var dark: Bool
        var draw: (inout GraphicsContext, CGPoint, CGFloat) -> Void
    }

    @ObservationIgnored private var images: [String: [Int: Image]] = [:]
    @ObservationIgnored private var costs: [String: Int] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var totalCost = 0
    @ObservationIgnored private var queue: [String: Request] = [:]
    @ObservationIgnored private var labels: [String: Image] = [:]
    @ObservationIgnored private var labelQueue: [String: () -> AnyView] = [:]
    @ObservationIgnored private var draining = false

    private static let step: CGFloat = 1.25
    private static let memoryBudget = 80 << 20

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { _ in
            SkySprites.shared.removeAll()
        }
    }

    /// The radius step at or above `radius`.
    static func bucket(for radius: CGFloat) -> Int {
        Int(ceil(log(max(radius, 1)) / log(step)))
    }

    static func radius(of bucket: Int) -> CGFloat { pow(step, CGFloat(bucket)) }

    /// The bitmap for `item` near `radius`, and the radius it was drawn at.
    /// Asks for the exact step when it's missing; meanwhile hands back the
    /// closest step already made (zooming), or nil (draw the original).
    func sprite(_ item: String, radius: CGFloat, maxRadius: CGFloat, extent: CGFloat, scale: CGFloat, dark: Bool,
                draw: @escaping (inout GraphicsContext, CGPoint, CGFloat) -> Void) -> (image: Image, radius: CGFloat)? {
        let key = dark ? item : item + "|dawn"
        let bucket = min(Self.bucket(for: radius), Self.bucket(for: maxRadius))
        let made = images[key]
        if let image = made?[bucket] { return (image, Self.radius(of: bucket)) }
        let id = "\(key)#\(bucket)"
        if queue[id] == nil {
            queue[id] = Request(item: key, bucket: bucket, radius: Self.radius(of: bucket), extent: extent,
                                scale: scale, dark: dark, draw: draw)
            scheduleDrain()
        }
        guard let made, let nearest = made.keys.min(by: { abs($0 - bucket) < abs($1 - bucket) }) else { return nil }
        return (made[nearest]!, Self.radius(of: nearest))
    }

    /// A label as a bitmap (typesetting every frame is the most expensive
    /// thing a sky can do), or nil until it's made.
    func label(_ key: String, scale: CGFloat, content: @escaping () -> AnyView) -> Image? {
        if let image = labels[key] { return image }
        if labelQueue[key] == nil {
            labelQueue[key] = content
            labelScale = scale
            scheduleDrain()
        }
        return nil
    }

    @ObservationIgnored private var labelScale: CGFloat = 3

    func removeAll() {
        labels = [:]
        images = [:]
        costs = [:]
        order = []
        totalCost = 0
    }

    // MARK: Making bitmaps

    private func scheduleDrain() {
        guard !draining else { return }
        draining = true
        DispatchQueue.main.async { [weak self] in self?.drain() }
    }

    /// Renders queued bitmaps for a few milliseconds, then yields to the next frame.
    private func drain() {
        let start = CACurrentMediaTime()
        var made = 0
        while let (key, content) = labelQueue.first, CACurrentMediaTime() - start < 0.006 || made == 0 {
            labelQueue[key] = nil
            let scale = labelScale
            // Main thread only (see the class note), so handing these over is safe.
            nonisolated(unsafe) let make = content
            if let cg = MainActor.assumeIsolated({ () -> CGImage? in
                let renderer = ImageRenderer(content: make())
                renderer.scale = scale
                return renderer.cgImage
            }) {
                labels[key] = Image(decorative: cg, scale: scale)
            }
            made += 1
        }
        while let (id, request) = queue.first, CACurrentMediaTime() - start < 0.006 || made == 0 {
            queue[id] = nil
            if images[request.item]?[request.bucket] == nil, let image = render(request) {
                store(image, for: request)
            }
            made += 1
        }
        if made > 0 { generation &+= 1 }
        if queue.isEmpty, labelQueue.isEmpty {
            draining = false
        } else {
            DispatchQueue.main.async { [weak self] in self?.drain() }
        }
    }

    private func render(_ r: Request) -> (Image, Int)? {
        let side = ceil(r.radius * r.extent)
        let draw = r.draw
        let radius = r.radius
        nonisolated(unsafe) let canvas = Canvas { ctx, size in
            draw(&ctx, CGPoint(x: size.width / 2, y: size.height / 2), radius)
        }
        .frame(width: side, height: side)
        .environment(\.colorScheme, r.dark ? .dark : .light)
        let scale = r.scale
        guard let cg = MainActor.assumeIsolated({ () -> CGImage? in
            let renderer = ImageRenderer(content: canvas)
            renderer.scale = scale
            renderer.isOpaque = false
            return renderer.cgImage
        }) else { return nil }
        return (Image(decorative: cg, scale: r.scale), cg.bytesPerRow * cg.height)
    }

    private func store(_ made: (Image, Int), for r: Request) {
        images[r.item, default: [:]][r.bucket] = made.0
        let id = "\(r.item)#\(r.bucket)"
        costs[id] = made.1
        order.append(id)
        totalCost += made.1
        // Oldest first, until back under budget.
        while totalCost > Self.memoryBudget, !order.isEmpty {
            let old = order.removeFirst()
            guard let cost = costs.removeValue(forKey: old), let hash = old.lastIndex(of: "#"),
                  let bucket = Int(old[old.index(after: hash)...]) else { continue }
            let item = String(old[..<hash])
            images[item]?[bucket] = nil
            if images[item]?.isEmpty == true { images[item] = nil }
            totalCost -= cost
        }
    }
}

extension GraphicsContext {
    /// Draws a sprite made at `madeRadius` so it matches `radius` at `center`.
    mutating func drawSprite(_ image: Image, madeRadius: CGFloat, extent: CGFloat, at center: CGPoint, radius: CGFloat) {
        let side = ceil(madeRadius * extent) * radius / madeRadius
        draw(image, in: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
    }
}
