import Foundation

/// The galaxies of the Odyssey. The first ten are hand-named; beyond that
/// they are generated, so the universe never runs out.
enum GalaxyCatalog {
    static let rules = OdysseyRules.standard

    private static let shapes: [GalaxyShape] = [.spiral2, .ring, .barred, .irregular, .spiral4, .elliptical]

    private static let colors: [(UInt32, UInt32, UInt32)] = [
        (0xFFF4D6, 0x8B7CFF, 0xFF8FB8),
        (0xFFE7A8, 0xFFB45C, 0x70E1F5),
        (0xF6D9FF, 0xB04BE0, 0x4B2A8C),
        (0xE8FFF6, 0x5FD6B5, 0x2E6B8C),
        (0xE6F2FF, 0x70A6FF, 0xC8F0FF),
        (0xFFE0D6, 0xFF7A6B, 0x8C2A4B),
        (0xFFFFFF, 0xFFD58A, 0x8B7CFF),
        (0xFFE9F6, 0xFF8FD8, 0x6B4BFF),
        (0xEAF7FF, 0x9EE8FF, 0x7A8CFF),
        (0xFFF8E6, 0xF2C46B, 0xD96BB0),
    ]

    static func name(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "Lumen Spiral")
        case 1: String(localized: "Aurelian Ring")
        case 2: String(localized: "Velvet Maw")
        case 3: String(localized: "Hollow Bloom")
        case 4: String(localized: "Tidecrown")
        case 5: String(localized: "Ashen Lyre")
        case 6: String(localized: "Seraph Wheel")
        case 7: String(localized: "Orchid Drift")
        case 8: String(localized: "Mirrorfall")
        case 9: String(localized: "Thousandfold")
        default: String(localized: "Uncharted Galaxy \(index + 1)")
        }
    }

    static func lore(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "Home. A young spiral where your first light was given to you.")
        case 1: String(localized: "A perfect ring of golden suns around an empty, quiet heart.")
        case 2: String(localized: "Deep violet dust swallows light, then gives it back as auroras.")
        case 3: String(localized: "A galaxy that grew outward like a flower, petal by petal.")
        case 4: String(localized: "Its arms rise and fall like tides around a crown of white stars.")
        case 5: String(localized: "Old, warm and humming: the oldest stars sing in low notes here.")
        case 6: String(localized: "Six radiant arms turn so slowly that they seem to stand still.")
        case 7: String(localized: "Pink nebulae drift between its stars like petals on water.")
        case 8: String(localized: "Every star here has a twin reflected across a silver lane.")
        case 9: String(localized: "So many folds of light that no map has ever finished it.")
        default: String(localized: "Beyond every chart. Only your light has reached this far.")
        }
    }

    static func blueprint(_ index: Int) -> GalaxyBlueprint {
        let seed = StableHash.fnv1a("lumora.galaxy.\(index)")
        var rng = SeededRandom(seed: seed)
        let c = colors[index % colors.count]
        let position: CGPoint
        if index == 0 {
            position = .zero
        } else {
            let angle = Double(index) * 2.399963 + 0.6
            let radius = 0.42 + 0.2 * Double(index).squareRoot()
            position = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }
        return GalaxyBlueprint(index: index, name: name(index), shape: shapes[index % shapes.count], seed: seed,
                               core: c.0, arm: c.1, dust: c.2, capacity: rules.galaxyCapacity(index),
                               mapPosition: position, tilt: rng.range(-0.6, 0.6), lore: lore(index))
    }
}
