import SwiftUI

// MARK: - Worlds

/// The class of a discoverable world. Twelve common classes and three
/// legendary ones. Every class has its own procedural art (`WorldPainter`)
/// and its own lore (`WorldLexicon`).
enum WorldArchetype: String, CaseIterable, Codable, Sendable {
    case verdant, oceanic, crystal, ember, glacier, gasGiant, machine, shattered, twin, phantom, dune, reef
    case ringworld, dysonPearl, livingEye

    static let common: [WorldArchetype] = [.verdant, .oceanic, .crystal, .ember, .glacier, .gasGiant,
                                           .machine, .shattered, .twin, .phantom, .dune, .reef]
    static let legendary: [WorldArchetype] = [.ringworld, .dysonPearl, .livingEye]

    var isLegendary: Bool { Self.legendary.contains(self) }

    var displayName: String {
        switch self {
        case .verdant: String(localized: "Verdant world")
        case .oceanic: String(localized: "Ocean world")
        case .crystal: String(localized: "Crystal world")
        case .ember: String(localized: "Ember world")
        case .glacier: String(localized: "Glacier world")
        case .gasGiant: String(localized: "Gas giant")
        case .machine: String(localized: "Clockwork world")
        case .shattered: String(localized: "Shattered world")
        case .twin: String(localized: "Twin worlds")
        case .phantom: String(localized: "Phantom world")
        case .dune: String(localized: "Dune world")
        case .reef: String(localized: "Reef world")
        case .ringworld: String(localized: "Ringworld")
        case .dysonPearl: String(localized: "Dyson Pearl")
        case .livingEye: String(localized: "The Living Eye")
        }
    }

    /// Typical surface temperature range (°C) for stats.
    var temperatureRange: ClosedRange<Int> {
        switch self {
        case .verdant: 12...34
        case .oceanic: 4...26
        case .crystal: (-60)...(10)
        case .ember: 380...920
        case .glacier: (-140)...(-40)
        case .gasGiant: (-180)...(-90)
        case .machine: 18...22
        case .shattered: (-90)...(140)
        case .twin: (-20)...(60)
        case .phantom: (-230)...(-160)
        case .dune: 30...74
        case .reef: 16...31
        case .ringworld: 18...24
        case .dysonPearl: 2000...6000
        case .livingEye: 36...38
        }
    }
}

enum WorldRarity: String, Codable, Sendable {
    case common, rare, legendary

    var label: String {
        switch self {
        case .common: String(localized: "Common")
        case .rare: String(localized: "Rare")
        case .legendary: String(localized: "Legendary")
        }
    }
}

/// A world's colours (sRGB hex). `WorldPainter` derives everything from these.
struct WorldPalette: Equatable, Sendable {
    var highlight: UInt32
    var mid: UInt32
    var shadow: UInt32
    var accent: UInt32
    var atmosphere: UInt32
}

/// What a world is, fully determined by its ordinal (and therefore stable
/// across launches and devices).
struct WorldBlueprint: Equatable, Sendable, Identifiable {
    var id: Int { ordinal }
    var ordinal: Int
    var seed: UInt64
    var archetype: WorldArchetype
    var rarity: WorldRarity
    var name: String
    var palette: WorldPalette
    var hasRings: Bool
    var moonCount: Int
    /// Light direction in radians (0 = from the right).
    var lightAngle: Double
    /// Axial tilt in radians, used for bands and rings.
    var tilt: Double
    var gravity: Double
    var dayLengthHours: Double
    var temperature: Int
    var loreVariant: Int
    var findIndex: Int
}

/// Terraforming stages. Each one is visibly more beautiful than the last.
enum WorldStage: Int, CaseIterable, Codable, Sendable, Comparable {
    case discovered = 0, breath, flow, bloom, lights, wonder

    static func < (a: WorldStage, b: WorldStage) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .discovered: String(localized: "Discovered")
        case .breath: String(localized: "Breath")
        case .flow: String(localized: "Flow")
        case .bloom: String(localized: "Bloom")
        case .lights: String(localized: "Lights")
        case .wonder: String(localized: "Wonder")
        }
    }

    /// What reaching this stage adds, shown as the "next" preview.
    var promise: String {
        switch self {
        case .discovered: String(localized: "Untouched, waiting.")
        case .breath: String(localized: "An atmosphere wraps the world in a soft glowing rim and drifting clouds.")
        case .flow: String(localized: "Seas, rivers or streams of light begin to move across the surface.")
        case .bloom: String(localized: "Life takes hold: luminous forests, reefs and spores glow in the dark.")
        case .lights: String(localized: "Cities wake up on the night side, and a station circles in orbit.")
        case .wonder: String(localized: "A wonder rises: a halo of light that can be seen from other galaxies.")
        }
    }

    var next: WorldStage? { WorldStage(rawValue: rawValue + 1) }
}

enum WorldStatus: String, Codable, Sendable {
    /// Visible on the map as a silhouette; nobody has been there.
    case uncharted
    /// Your ship is travelling there.
    case enRoute
    /// Visited: lore, stats and the find are revealed, terraforming unlocked.
    case charted
}

/// Something found on arrival (a lifeform, relic or phenomenon) for the codex.
struct WorldFind: Equatable, Sendable {
    enum Kind: String, Sendable { case lifeform, relic, phenomenon }
    var kind: Kind
    var title: String
    var detail: String

    var kindLabel: String {
        switch kind {
        case .lifeform: String(localized: "Lifeform")
        case .relic: String(localized: "Relic")
        case .phenomenon: String(localized: "Phenomenon")
        }
    }
}

// MARK: - Galaxies

enum GalaxyShape: String, Codable, Sendable, CaseIterable {
    case spiral2, spiral4, barred, ring, elliptical, irregular
}

struct GalaxyBlueprint: Equatable, Sendable, Identifiable {
    var id: Int { index }
    var index: Int
    var name: String
    var shape: GalaxyShape
    var seed: UInt64
    /// Core, arm and dust colours (sRGB hex).
    var core: UInt32
    var arm: UInt32
    var dust: UInt32
    /// Worlds this galaxy holds before the next one ignites.
    var capacity: Int
    /// Position on the cosmic map, normalized to roughly -1...1.
    var mapPosition: CGPoint
    var tilt: Double
    var lore: String
}

// MARK: - Ship

enum ShipHull: String, CaseIterable, Codable, Sendable {
    case lantern, swift, ark, manta
    var title: String {
        switch self {
        case .lantern: String(localized: "Lantern")
        case .swift: String(localized: "Swift")
        case .ark: String(localized: "Ark")
        case .manta: String(localized: "Manta")
        }
    }
}

enum ShipPaint: String, CaseIterable, Codable, Sendable {
    case pearl, nebula, aurora, solar, abyss
    /// Orbi+ finishes, still bought with stardust.
    case eclipse, opal
    var title: String {
        switch self {
        case .pearl: String(localized: "Pearl")
        case .nebula: String(localized: "Nebula")
        case .aurora: String(localized: "Aurora")
        case .solar: String(localized: "Solar")
        case .abyss: String(localized: "Abyss")
        case .eclipse: String(localized: "Eclipse")
        case .opal: String(localized: "Opal")
        }
    }
    /// Body, trim and window colours.
    var colors: (body: UInt32, trim: UInt32, window: UInt32) {
        switch self {
        case .pearl: (0xF2F1FA, 0x8B7CFF, 0x70E1F5)
        case .nebula: (0x5B4BE0, 0xFF8FB8, 0xFFD58A)
        case .aurora: (0x2FD6B5, 0x70E1F5, 0xE9E4FF)
        case .solar: (0xFFD58A, 0xFF8A3D, 0xFFF6E0)
        case .abyss: (0x1B1E3D, 0x70E1F5, 0x8B7CFF)
        case .eclipse: (0x0D0E1A, 0xFFD58A, 0xFF8A3D)
        case .opal: (0xE6F7F4, 0xFF8FB8, 0x8B7CFF)
        }
    }
}

enum ShipTrail: String, CaseIterable, Codable, Sendable {
    case ion, solar, aurora, comet
    /// Earned only by a chain of horizons reached in a row; never sold.
    case dawnline, starlit, prism
    /// A Orbi+ trail, still bought with stardust.
    case supernova
    var title: String {
        switch self {
        case .ion: String(localized: "Ion")
        case .solar: String(localized: "Solar flare")
        case .aurora: String(localized: "Aurora")
        case .comet: String(localized: "Comet tail")
        case .dawnline: String(localized: "Dawnline")
        case .starlit: String(localized: "Starlit wake")
        case .prism: String(localized: "Prism")
        case .supernova: String(localized: "Supernova")
        }
    }
    /// Inner and outer flame colours.
    var colors: (inner: UInt32, outer: UInt32) {
        switch self {
        case .ion: (0xE9FBFF, 0x70E1F5)
        case .solar: (0xFFF3C4, 0xFF8A3D)
        case .aurora: (0xE2FFF1, 0x8B7CFF)
        case .comet: (0xFFFFFF, 0xFFD58A)
        case .dawnline: (0xFFF1E0, 0xFF8FB8)
        case .starlit: (0xFFFFFF, 0xC7B8FF)
        case .prism: (0xE9FFFB, 0x2FD6B5)
        case .supernova: (0xFFFFFF, 0xFF5E7E)
        }
    }

    /// Horizons reached in a row that unlock this trail, for chain trails.
    var chainRequirement: Int? {
        switch self {
        case .dawnline: 2
        case .starlit: 4
        case .prism: 6
        default: nil
        }
    }
}

struct ShipLoadout: Equatable, Sendable {
    var hull: ShipHull = .lantern
    var paint: ShipPaint = .pearl
    var trail: ShipTrail = .ion

    /// The same ship with any Orbi+ finish swapped for the starter one.
    var withoutPlus: ShipLoadout {
        var l = self
        if ShipPart.paint(paint).isPlus { l.paint = .pearl }
        if ShipPart.trail(trail).isPlus { l.trail = .ion }
        return l
    }
}

/// Anything the hangar sells. Raw values are stable storage keys.
enum ShipPart: Hashable, Sendable {
    case hull(ShipHull), paint(ShipPaint), trail(ShipTrail)

    var key: String {
        switch self {
        case let .hull(h): "hull.\(h.rawValue)"
        case let .paint(p): "paint.\(p.rawValue)"
        case let .trail(t): "trail.\(t.rawValue)"
        }
    }

    init?(key: String) {
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "hull": guard let h = ShipHull(rawValue: parts[1]) else { return nil }; self = .hull(h)
        case "paint": guard let p = ShipPaint(rawValue: parts[1]) else { return nil }; self = .paint(p)
        case "trail": guard let t = ShipTrail(rawValue: parts[1]) else { return nil }; self = .trail(t)
        default: return nil
        }
    }

    var title: String {
        switch self {
        case let .hull(h): h.title
        case let .paint(p): p.title
        case let .trail(t): t.title
        }
    }

    /// Finishes that need Orbi+ to buy and to wear.
    var isPlus: Bool {
        switch self {
        case .paint(.eclipse), .paint(.opal), .trail(.supernova): true
        default: false
        }
    }

    static let starter: Set<ShipPart> = [.hull(.lantern), .paint(.pearl), .trail(.ion)]

    static var all: [ShipPart] {
        ShipHull.allCases.map(ShipPart.hull) + ShipPaint.allCases.map(ShipPart.paint) + ShipTrail.allCases.map(ShipPart.trail)
    }
}

// MARK: - Ranks

struct NavigatorRank: Equatable, Sendable, Identifiable {
    var id: Int { level }
    var level: Int
    var title: String
    var minXP: Int

    static let all: [NavigatorRank] = [
        .init(level: 1, title: String(localized: "Cadet"), minXP: 0),
        .init(level: 2, title: String(localized: "Pathfinder"), minXP: 150),
        .init(level: 3, title: String(localized: "Navigator"), minXP: 500),
        .init(level: 4, title: String(localized: "Star Cartographer"), minXP: 1_200),
        .init(level: 5, title: String(localized: "Worldshaper"), minXP: 2_500),
        .init(level: 6, title: String(localized: "Galaxy Warden"), minXP: 5_000),
        .init(level: 7, title: String(localized: "Architect of Light"), minXP: 9_000),
        .init(level: 8, title: String(localized: "Keeper of Many Skies"), minXP: 15_000),
    ]

    static func rank(forXP xp: Int) -> NavigatorRank {
        all.last { xp >= $0.minXP } ?? all[0]
    }

    var next: NavigatorRank? { Self.all.first { $0.level == level + 1 } }
}

// MARK: - Horizons (goals)

enum HorizonKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case weeklyHours, chartWorlds, cultivate, sessions, rhythm
    var id: String { rawValue }

    var title: String {
        switch self {
        case .weeklyHours: String(localized: "Hours of light this week")
        case .chartWorlds: String(localized: "Chart new worlds")
        case .cultivate: String(localized: "Terraform stages")
        case .sessions: String(localized: "Focus sessions")
        case .rhythm: String(localized: "Days of rhythm")
        }
    }

    /// Sensible choices, gentlest first.
    var presets: [Int] {
        switch self {
        case .weeklyHours: [3, 5, 8, 12, 20]
        case .chartWorlds: [1, 2, 3, 5]
        case .cultivate: [2, 3, 5, 8]
        case .sessions: [5, 10, 20, 30]
        case .rhythm: [3, 5, 7, 14, 21]
        }
    }

    var symbol: String {
        switch self {
        case .weeklyHours: "sun.max"
        case .chartWorlds: "scope"
        case .cultivate: "leaf"
        case .sessions: "sparkles"
        case .rhythm: "moon.stars"
        }
    }

    /// Weekly goals end after 7 days; the rest have no deadline.
    var isWeekly: Bool { self == .weeklyHours }

    func rewardStardust(target: Int) -> Int {
        switch self {
        case .weeklyHours: 40 + target * 20
        case .chartWorlds: 30 + target * 40
        case .cultivate: 20 + target * 30
        case .sessions: 20 + target * 8
        case .rhythm: 20 + target * 12
        }
    }

    func progressLabel(progress: Int, target: Int) -> String {
        switch self {
        case .weeklyHours: String(localized: "\(LMFormat.minutes(progress)) of \(target)h")
        default: String(localized: "\(progress) of \(target)")
        }
    }

    /// The goal measures minutes for weekly hours, raw counts otherwise.
    func targetUnits(_ target: Int) -> Int { self == .weeklyHours ? target * 60 : target }
}

// MARK: - Rare events

/// Once a week, something rare crosses your sky. Focus that day to witness it.
enum CosmicEventKind: String, CaseIterable, Codable, Sendable {
    case comet, eclipse, meteors, aurora, twinSuns, nova
    case alignment, solarStorm, pulsar, moonHalo, nebulaBloom

    var title: String {
        switch self {
        case .comet: String(localized: "The Veyra Comet passes")
        case .eclipse: String(localized: "A galaxy eclipse")
        case .meteors: String(localized: "The Ember Shower")
        case .aurora: String(localized: "The Great Veil")
        case .twinSuns: String(localized: "Twin sunrise")
        case .nova: String(localized: "A new star blooms")
        case .alignment: String(localized: "The Great Alignment")
        case .solarStorm: String(localized: "A solar storm")
        case .pulsar: String(localized: "The pulsar's song")
        case .moonHalo: String(localized: "A halo round the moon")
        case .nebulaBloom: String(localized: "A nebula blooms")
        }
    }

    var lore: String {
        switch self {
        case .comet: String(localized: "It returns once in a long while, trailing a tail of pale gold across the whole sky.")
        case .eclipse: String(localized: "A dark world slides in front of a distant galaxy, and for a moment it wears a ring of light.")
        case .meteors: String(localized: "Thousands of tiny embers fall through the night, each one a wish someone forgot to make.")
        case .aurora: String(localized: "Curtains of green and violet light ripple from one edge of the sky to the other.")
        case .twinSuns: String(localized: "Two suns rise together over the far worlds, and every shadow comes in pairs.")
        case .nova: String(localized: "A faint star suddenly blooms, brighter than anything near it, then slowly settles.")
        case .alignment: String(localized: "For one night the far worlds stand in a single line, as if waiting for someone to notice.")
        case .solarStorm: String(localized: "A distant sun throws arcs of fire into the dark, and every sky downwind glows.")
        case .pulsar: String(localized: "A dead star spins so fast its light sweeps past like a lighthouse, keeping perfect time.")
        case .moonHalo: String(localized: "Ice high in the air paints a pale ring round the moon, wide as the sky can hold.")
        case .nebulaBloom: String(localized: "A cloud of dust and gas catches new starlight and opens like a flower.")
        }
    }

    /// What the Codex records once you've seen it.
    var codexLine: String {
        switch self {
        case .comet: String(localized: "You saw the Veyra Comet cross your sky.")
        case .eclipse: String(localized: "You watched a galaxy wear a ring of light.")
        case .meteors: String(localized: "You stood under the Ember Shower.")
        case .aurora: String(localized: "You saw the Great Veil ripple across the sky.")
        case .twinSuns: String(localized: "You watched two suns rise together.")
        case .nova: String(localized: "You saw a new star bloom.")
        case .alignment: String(localized: "You saw the far worlds stand in a line.")
        case .solarStorm: String(localized: "You watched a sun throw arcs of fire.")
        case .pulsar: String(localized: "You kept time with a pulsar.")
        case .moonHalo: String(localized: "You saw a halo round the moon.")
        case .nebulaBloom: String(localized: "You watched a nebula bloom.")
        }
    }
}

/// A rare event on one day of one week.
struct CosmicEvent: Equatable, Sendable, Identifiable {
    var id: DayKey { day }
    var kind: CosmicEventKind
    var day: DayKey
    var date: Date
}

/// One event per week (Monday to Sunday), on a day and of a kind chosen by
/// a stable hash of the week, so everyone's calendar is the same and
/// nothing depends on randomness at runtime.
enum CosmicCalendar {
    #if DEBUG
    /// Debug (`-lumora-event-today <kind>`): this week's event falls today.
    nonisolated(unsafe) static var forcedToday: CosmicEventKind?
    #endif

    static func event(inWeekOf date: Date, calendar: Calendar) -> CosmicEvent {
        #if DEBUG
        if let kind = forcedToday {
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = calendar.timeZone
            if iso.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
                let today = iso.startOfDay(for: Date())
                return CosmicEvent(kind: kind, day: DayKey(today, calendar: iso), date: today)
            }
        }
        #endif
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let week = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let start = iso.date(from: week) ?? iso.startOfDay(for: date)
        let seed = StableHash.fnv1a("lumora.event.\(week.yearForWeekOfYear ?? 0)-\(week.weekOfYear ?? 0)")
        let day = iso.date(byAdding: .day, value: Int(seed % 7), to: start) ?? start
        let kinds = CosmicEventKind.allCases
        return CosmicEvent(kind: kinds[Int((seed >> 16) % UInt64(kinds.count))], day: DayKey(day, calendar: iso), date: day)
    }

    /// This week's event if it hasn't passed, otherwise next week's.
    static func upcoming(from date: Date, calendar: Calendar) -> CosmicEvent {
        let this = event(inWeekOf: date, calendar: calendar)
        if this.day >= DayKey(date, calendar: calendar) { return this }
        return event(inWeekOf: date.addingTimeInterval(7 * 86_400), calendar: calendar)
    }
}
