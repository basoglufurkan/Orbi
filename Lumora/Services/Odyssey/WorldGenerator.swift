import Foundation

/// Deterministic world generation: the same ordinal always yields the same
/// world, on every device, forever. Uses `SeededRandom` (SplitMix64) and
/// `StableHash` only — never `Hasher` or system randomness.
enum WorldGenerator {
    /// The first deck is hand-ordered so the opening worlds are the most striking.
    private static let firstDeck: [WorldArchetype] = [.verdant, .gasGiant, .crystal, .oceanic, .ember, .twin,
                                                      .glacier, .machine, .reef, .phantom, .dune, .shattered]

    static func seed(forWorld ordinal: Int) -> UInt64 {
        StableHash.fnv1a("lumora.world.\(ordinal)")
    }

    static func blueprint(ordinal: Int) -> WorldBlueprint {
        let seed = seed(forWorld: ordinal)
        var rng = SeededRandom(seed: seed)

        // Every 9th world is legendary; the rest walk shuffled decks of the
        // twelve common classes, so no class repeats until all were seen.
        let archetype: WorldArchetype
        let rarity: WorldRarity
        if ordinal % 9 == 0 {
            archetype = WorldArchetype.legendary[(ordinal / 9 - 1) % WorldArchetype.legendary.count]
            rarity = .legendary
        } else {
            let serial = ordinal - ordinal / 9          // position among common worlds
            let deck = (serial - 1) / 12, slot = (serial - 1) % 12
            if deck == 0 {
                archetype = firstDeck[slot]
            } else {
                var deckRng = SeededRandom(seed: StableHash.fnv1a("lumora.deck.\(deck)"))
                archetype = WorldArchetype.common.shuffled(using: &deckRng)[slot]
            }
            rarity = (seed % 5 == 0) ? .rare : .common
        }

        let palettes = palettes(for: archetype)
        let palette = palettes[Int(rng.next() % UInt64(palettes.count))]
        let hasRings = archetype == .gasGiant || archetype == .ringworld || (archetype != .twin && rng.next() % 4 == 0)
        let moons = archetype == .twin ? 0 : Int(rng.next() % 4)
        let temp = archetype.temperatureRange
        let gravity = archetype == .gasGiant ? rng.range(2.1, 3.6) : rng.range(0.3, 2.2)

        return WorldBlueprint(
            ordinal: ordinal, seed: seed, archetype: archetype, rarity: rarity,
            name: name(seed: seed, legendary: rarity == .legendary),
            palette: palette, hasRings: hasRings, moonCount: moons,
            lightAngle: -2.3 + rng.range(-0.35, 0.35),
            tilt: rng.range(-0.45, 0.45),
            gravity: (gravity * 10).rounded() / 10,
            dayLengthHours: (rng.range(5, 90) * 10).rounded() / 10,
            temperature: temp.lowerBound + Int(rng.next() % UInt64(temp.count)),
            loreVariant: Int(rng.next() % 3),
            findIndex: findIndex(ordinal: ordinal))
    }

    /// Finds walk a fixed shuffle so early worlds never repeat a discovery.
    static func findIndex(ordinal: Int) -> Int {
        let count = max(1, WorldLexicon.findCount)
        var rng = SeededRandom(seed: 0x0D15_C0FE)
        let order = Array(0..<count).shuffled(using: &rng)
        return order[(ordinal - 1) % count]
    }

    // MARK: Names

    private static let starts = ["Ka", "Ve", "Or", "Sy", "Tha", "Ae", "Lu", "Mi", "Ze", "Qua", "Ny", "Ix", "Sol", "Ri",
                                 "Va", "Elo", "Cy", "Dra", "Hal", "Ume", "Bel", "Ish", "Oru", "Tey", "Fen", "Ros"]
    private static let middles = ["ra", "li", "no", "the", "vi", "ssa", "ru", "ae", "lo", "ma", "ne", "", "", "ri", "ka"]
    private static let ends = ["th", "n", "ra", "ix", "os", "eon", "ia", "ar", "is", "um", "el", "yx", "ine", "ora", "us"]
    private static let suffixes = ["", "", "", "", " Prime", "-7", " IV", " b", " Minor", "-12", " II"]

    static func name(seed: UInt64, legendary: Bool) -> String {
        var rng = SeededRandom(seed: seed ^ 0x4E41_4D45)
        func pick(_ list: [String]) -> String { list[Int(rng.next() % UInt64(list.count))] }
        let core = pick(starts) + pick(middles) + pick(ends)
        return legendary ? core : core + pick(suffixes)
    }

    // MARK: Palettes

    static func palettes(for archetype: WorldArchetype) -> [WorldPalette] {
        func p(_ h: UInt32, _ m: UInt32, _ s: UInt32, _ a: UInt32, _ at: UInt32) -> WorldPalette {
            WorldPalette(highlight: h, mid: m, shadow: s, accent: a, atmosphere: at)
        }
        switch archetype {
        case .verdant: return [p(0xD9FFB8, 0x3FB27F, 0x123A3A, 0x7CFFCB, 0x9BF0FF), p(0xF0FFC9, 0x7BBF4A, 0x1D3B2A, 0xFFE27A, 0xB6F5E0)]
        case .oceanic: return [p(0xC9F6FF, 0x2F7FD8, 0x0B1F4A, 0xE8FFFF, 0x7FD3FF), p(0xD6FFF5, 0x1FA6A0, 0x08303F, 0xFFFFFF, 0x8FF0E0)]
        case .crystal: return [p(0xFFFFFF, 0xB59CFF, 0x2A1F6B, 0x70E1F5, 0xE6DCFF), p(0xFFF7FB, 0xFF9FD0, 0x4A1640, 0xFFE8A3, 0xFFD6EC)]
        case .ember: return [p(0xFFE2A8, 0xC2412D, 0x2A0B0E, 0xFFB13D, 0xFF7A45), p(0xFFD3B0, 0x8A2B4A, 0x1B0716, 0xFF6A3D, 0xFF9A6B)]
        case .glacier: return [p(0xFFFFFF, 0xA9D8F2, 0x2E4B73, 0x7DF9FF, 0xC9F2FF), p(0xF4FBFF, 0xC4C9F5, 0x343A6E, 0x9EFFD8, 0xDDE4FF)]
        case .gasGiant: return [p(0xFFE9C2, 0xE3A15C, 0x5A2F2A, 0xFFF4DE, 0xFFD39A), p(0xE4E6FF, 0x8A93E8, 0x26285E, 0xF2C6FF, 0xB9C2FF), p(0xD8FFF0, 0x5FC7B5, 0x1B3F4F, 0xFFE9A8, 0xA8F5E5)]
        case .machine: return [p(0xE9ECF5, 0x7A8296, 0x1A1D2B, 0xFFD58A, 0xB7C4FF), p(0xE6FFF9, 0x4F7C83, 0x0E1C22, 0x70E1F5, 0x9BEFFF)]
        case .shattered: return [p(0xF2D7C6, 0x8B6B5C, 0x24161A, 0xFF8FB8, 0xFFB7A3), p(0xD9E1F5, 0x6A6F92, 0x1A1B33, 0x8B7CFF, 0xB6B9FF)]
        case .twin: return [p(0xFFE3C9, 0xE07A5F, 0x3D1E2E, 0x70E1F5, 0xFFC1A6), p(0xE0F0FF, 0x6C8EEB, 0x1D2459, 0xFFD58A, 0xB2C8FF)]
        case .phantom: return [p(0xF5F0FF, 0x9E8CFF, 0x1E1446, 0xE7FFFE, 0xD8CCFF), p(0xEFFFFB, 0x78D9CF, 0x0F2E36, 0xFFFFFF, 0xC8FFF6)]
        case .dune: return [p(0xFFF1D1, 0xD9A25F, 0x5B3020, 0x70E1F5, 0xFFD9A8), p(0xFFE4E0, 0xC97B6B, 0x4A1F2A, 0xFFD58A, 0xFFC4B8)]
        case .reef: return [p(0xFFE6F2, 0xFF7FB0, 0x3E1145, 0x7CF5FF, 0xFFC2DE), p(0xF2FFE9, 0xFF9F7A, 0x1F3550, 0x6CFFD2, 0xFFD3B8)]
        case .ringworld: return [p(0xFFFFFF, 0x9FB4D9, 0x1C2440, 0xFFD58A, 0xC7D8FF)]
        case .dysonPearl: return [p(0xFFFBEA, 0xFFC46B, 0x3D1E0A, 0x70E1F5, 0xFFE3A0)]
        case .livingEye: return [p(0xFFF0F5, 0xE65A8D, 0x2B0A2E, 0x7CFFCB, 0xFFB3CF)]
        }
    }
}
