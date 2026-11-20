import Foundation

/// SplitMix64: a tiny, fast, *stable* PRNG. Unlike `SystemRandomNumberGenerator`
/// its output depends only on the seed, so the same user data always produces
/// the same universe across launches, devices and OS versions.
struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * unit()
    }
}

enum StableHash {
    /// FNV-1a over UTF-8; stable across launches (unlike `Hasher`).
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// Integer mixing for procedural fields (e.g. background star cells).
    static func mix(_ a: Int, _ b: Int, _ salt: UInt64 = 0) -> UInt64 {
        var r = SeededRandom(seed: UInt64(bitPattern: Int64(a)) &* 0x9E37_79B9 ^ UInt64(bitPattern: Int64(b)) &* 0x85EB_CA6B ^ salt)
        return r.next()
    }
}
