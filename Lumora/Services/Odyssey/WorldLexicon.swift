import Foundation

/// Words for worlds: class lore and arrival finds. Full sentences only,
/// so every line can be translated naturally. Every string is a literal
/// inside `String(localized:)` so the String Catalog can extract it.
enum WorldLexicon {
    /// One short line describing what a class of world is like.
    static func tagline(_ archetype: WorldArchetype) -> String {
        switch archetype {
        case .verdant: String(localized: "Forests that glow when the wind passes through them.")
        case .oceanic: String(localized: "One endless ocean, and storms that sing.")
        case .crystal: String(localized: "A world of facets that splits starlight into colour.")
        case .ember: String(localized: "Rivers of light run through a crust of black glass.")
        case .glacier: String(localized: "Ice so deep it remembers every sunrise.")
        case .gasGiant: String(localized: "A giant of clouds, banded like a slow song.")
        case .machine: String(localized: "Gears the size of continents, still turning.")
        case .shattered: String(localized: "Broken long ago, still holding its pieces close.")
        case .twin: String(localized: "Two worlds that never stop dancing.")
        case .phantom: String(localized: "Half there, half dream: a world made of mist.")
        case .dune: String(localized: "Golden seas of sand that move like water.")
        case .reef: String(localized: "Coral continents under a pink, shallow sea.")
        case .ringworld: String(localized: "Someone built a ring around a star, and left a light on.")
        case .dysonPearl: String(localized: "A star wrapped in a shell of mirrors.")
        case .livingEye: String(localized: "A world that looks back at you.")
        }
    }

    // MARK: - Lore

    /// What it is like to arrive. Three variants per class; any `variant`
    /// is accepted and folded into 0...2.
    static func lore(_ archetype: WorldArchetype, variant: Int) -> String {
        let v = ((variant % 3) + 3) % 3
        switch archetype {
        case .verdant:
            switch v {
            case 0: return String(localized: "You land in a meadow that hums softly. Every leaf turns, slowly, to see who has arrived.")
            case 1: return String(localized: "The trees breathe out light at dusk, and the whole forest glows like a sleeping lantern.")
            default: return String(localized: "Moss as soft as velvet covers everything. Somewhere nearby, a flower is opening just for you.")
            }
        case .oceanic:
            switch v {
            case 0: return String(localized: "There is no shore, only water to every horizon, and waves that rise and fall like slow breathing.")
            case 1: return String(localized: "Your ship settles on a floating island of kelp. Far below, great shapes glide by, unhurried.")
            default: return String(localized: "At night the sea glows from beneath, and the distant storms sing in long, low chords.")
            }
        case .crystal:
            switch v {
            case 0: return String(localized: "Every step rings like a small bell. Sunlight sinks into the ground and comes back out as rainbows.")
            case 1: return String(localized: "Towers of quartz grow here, a finger’s width each century. They are in no hurry, and neither are you.")
            default: return String(localized: "The plains are clear as glass. Look down, and you can see starlight caught deep inside the world.")
            }
        case .ember:
            switch v {
            case 0: return String(localized: "The ground is black glass, warm to the touch, and rivers of light move beneath it like slow thoughts.")
            case 1: return String(localized: "Night never quite falls here. The volcanoes glow a gentle orange, like coals in a quiet hearth.")
            default: return String(localized: "Sparks drift up through the warm air and become, for a moment, brand new constellations.")
            }
        case .glacier:
            switch v {
            case 0: return String(localized: "Blue ice stretches in every direction, silent and deep. Inside it, old sunrises are still glowing.")
            case 1: return String(localized: "Snow falls so slowly here that you can follow a single flake for a whole minute.")
            default: return String(localized: "Beneath the ice, a calm sea moves in the dark, and every so often the glacier lets out a long sigh.")
            }
        case .gasGiant:
            switch v {
            case 0: return String(localized: "There is no ground to land on. You drift among bands of cloud, each one moving to its own slow music.")
            case 1: return String(localized: "A storm older than memory turns below you, calm at its centre and wide as a hundred worlds.")
            default: return String(localized: "Lightning flickers deep in the clouds, soft as a heartbeat, and the whole sky glows amber.")
            }
        case .machine:
            switch v {
            case 0: return String(localized: "Gears the size of mountains turn without a sound. Someone set this world in motion, and it never stopped.")
            case 1: return String(localized: "Brass valleys tick softly in the evening light. The whole planet keeps perfect time.")
            default: return String(localized: "Little lights blink along the canyons, as if the world is quietly thinking something through.")
            }
        case .shattered:
            switch v {
            case 0: return String(localized: "The pieces of this world float in a slow ring, close enough to wave from one to the next.")
            case 1: return String(localized: "Waterfalls pour from one fragment to another and drift away as silver mist.")
            default: return String(localized: "It broke long ago, gently. Now every shard has its own small sky and its own small sunset.")
            }
        case .twin:
            switch v {
            case 0: return String(localized: "Two worlds circle so closely that their skies almost touch. Overhead, the other one’s forests are in bloom.")
            case 1: return String(localized: "When the twins pass near, a bridge of cloud forms between them, and flocks of birds fly across.")
            default: return String(localized: "One world holds the day, the other the night, and they trade places like old friends taking turns.")
            }
        case .phantom:
            switch v {
            case 0: return String(localized: "Your ship lands softly on something that is almost ground. The mist parts, then closes, then parts again.")
            case 1: return String(localized: "Half the time this world is here, and half the time it is a dream of itself. Today, it let you in.")
            default: return String(localized: "Hills and rivers drift through the fog, there and gone again, like a song half remembered.")
            }
        case .dune:
            switch v {
            case 0: return String(localized: "Golden dunes roll like a sea that moves one grain at a time. The sand is warm and sings as you walk.")
            case 1: return String(localized: "The wind writes long, curving lines across the desert all day, and kindly erases them by morning.")
            default: return String(localized: "Two suns set together here, and the dunes turn from gold to rose to violet.")
            }
        case .reef:
            switch v {
            case 0: return String(localized: "A pink, shallow sea covers everything, so clear that the coral continents seem to float in the air.")
            case 1: return String(localized: "Tiny lights drift through the warm water, and the reefs answer them in colour.")
            default: return String(localized: "The tide comes in once a day, slow and gentle, and the whole world smells of salt and flowers.")
            }
        case .ringworld:
            switch v {
            case 0: return String(localized: "A ribbon of land wraps all the way around a star. Look up, and the far side of the ring arches across the sky.")
            case 1: return String(localized: "Whoever built this ring left the gardens tended and the lights on, as if they knew someone would come.")
            default: return String(localized: "Rivers here flow for thousands of kilometres and never reach a sea. The ring simply has no end.")
            }
        case .dysonPearl:
            switch v {
            case 0: return String(localized: "A star hides inside a shell of mirrors. Through small gaps, its light spills out in long golden beams.")
            case 1: return String(localized: "The shell is smooth and warm as a pearl. Somewhere deep inside, the star is humming to itself.")
            default: return String(localized: "Each mirror tilts a little every day, slowly turning the starlight toward somewhere far away.")
            }
        case .livingEye:
            switch v {
            case 0: return String(localized: "As you arrive, the great iris turns, slowly, and settles on your ship. It does not seem surprised.")
            case 1: return String(localized: "This world blinks once every thousand years. You arrived just in time to see it.")
            default: return String(localized: "Its gaze is warm and patient, like someone who has waited a very long time for a visitor.")
            }
        }
    }

    // MARK: - Finds

    /// Number of distinct finds. `WorldGenerator` picks `findIndex` in `0..<findCount`.
    static let findCount = 51

    /// A find for the codex. Any `index` is accepted and wrapped safely.
    static func find(_ index: Int) -> WorldFind {
        let i = ((index % findCount) + findCount) % findCount
        switch i {
        // Lifeforms
        case 0: return WorldFind(kind: .lifeform, title: String(localized: "Glass moths"),
                                 detail: String(localized: "They gather around anything that has been still for a long time."))
        case 1: return WorldFind(kind: .lifeform, title: String(localized: "Lantern whales"),
                                 detail: String(localized: "They swim through the upper clouds, lighting the way for anything that is lost."))
        case 2: return WorldFind(kind: .lifeform, title: String(localized: "Humming moss"),
                                 detail: String(localized: "It hums a little louder whenever someone nearby is concentrating."))
        case 3: return WorldFind(kind: .lifeform, title: String(localized: "Echo foxes"),
                                 detail: String(localized: "Small, curious foxes that repeat your last word, very softly, a few seconds later."))
        case 4: return WorldFind(kind: .lifeform, title: String(localized: "Tortoise mountains"),
                                 detail: String(localized: "What looked like hills were tortoises, settling in for a nap of three centuries."))
        case 5: return WorldFind(kind: .lifeform, title: String(localized: "Orbit seeds"),
                                 detail: String(localized: "Seeds that drift up into orbit and sprout on whichever moon they reach first."))
        case 6: return WorldFind(kind: .lifeform, title: String(localized: "Origami birds"),
                                 detail: String(localized: "They fold themselves out of fallen leaves and unfold again when they land."))
        case 7: return WorldFind(kind: .lifeform, title: String(localized: "Bell flowers"),
                                 detail: String(localized: "Each one rings a single note when touched, and no two notes are the same."))
        case 8: return WorldFind(kind: .lifeform, title: String(localized: "Cloud jellyfish"),
                                 detail: String(localized: "They float through the warm air like paper lanterns and pulse slowly when it rains."))
        case 9: return WorldFind(kind: .lifeform, title: String(localized: "Scribe worms"),
                                 detail: String(localized: "They leave neat lines of glowing script in the sand. Nobody has translated it yet."))
        case 10: return WorldFind(kind: .lifeform, title: String(localized: "Patient trees"),
                                  detail: String(localized: "They grow one ring each century and remember the weather of every single year."))
        case 11: return WorldFind(kind: .lifeform, title: String(localized: "Dawn-sipping crabs"),
                                  detail: String(localized: "They lift their shells at sunrise to drink the first light, then go back to sleep."))
        case 12: return WorldFind(kind: .lifeform, title: String(localized: "Whisper owls"),
                                  detail: String(localized: "They call only when the whole forest is quiet, and their call sounds like a soft question."))
        case 13: return WorldFind(kind: .lifeform, title: String(localized: "Velvet grazers"),
                                  detail: String(localized: "Round, gentle creatures that eat only fallen starlight and purr when they are full."))
        case 14: return WorldFind(kind: .lifeform, title: String(localized: "Mirror fish"),
                                  detail: String(localized: "Their scales reflect the sky so well that a passing school looks like a window in the sea."))
        case 15: return WorldFind(kind: .lifeform, title: String(localized: "Kite lilies"),
                                  detail: String(localized: "On windy days they let go of their roots and fly, then settle somewhere new."))
        case 16: return WorldFind(kind: .lifeform, title: String(localized: "Lullaby coral"),
                                  detail: String(localized: "When the tide goes out, the coral sings the whole reef to sleep."))

        // Relics
        case 17: return WorldFind(kind: .relic, title: String(localized: "The humming obelisk"),
                                  detail: String(localized: "It hums a single note, and the note is slightly different for every visitor."))
        case 18: return WorldFind(kind: .relic, title: String(localized: "A library of stones"),
                                  detail: String(localized: "Smooth stones stacked in tidy rows. Hold one to your ear and it tells you a story."))
        case 19: return WorldFind(kind: .relic, title: String(localized: "The last lighthouse"),
                                  detail: String(localized: "It still turns and still shines, guiding ships that stopped coming long ago."))
        case 20: return WorldFind(kind: .relic, title: String(localized: "An unfinished map"),
                                  detail: String(localized: "A beautiful map of this galaxy, with one corner left blank, as if saved for you."))
        case 21: return WorldFind(kind: .relic, title: String(localized: "A garden of clocks"),
                                  detail: String(localized: "Dozens of clocks planted in a field, each one keeping the time of a different world."))
        case 22: return WorldFind(kind: .relic, title: String(localized: "The patient bench"),
                                  detail: String(localized: "A stone bench facing the finest view on the planet, worn smooth by countless quiet hours."))
        case 23: return WorldFind(kind: .relic, title: String(localized: "A letter in a bottle"),
                                  detail: String(localized: "Sealed in glass and written in a language of dots. It seems to be a thank-you note."))
        case 24: return WorldFind(kind: .relic, title: String(localized: "The singing bridge"),
                                  detail: String(localized: "A bridge over nothing at all. Cross it, and it plays a short, cheerful tune."))
        case 25: return WorldFind(kind: .relic, title: String(localized: "A vault of starseeds"),
                                  detail: String(localized: "Thousands of tiny glass jars, each holding one small star, fast asleep."))
        case 26: return WorldFind(kind: .relic, title: String(localized: "The sleeping robot"),
                                  detail: String(localized: "A little robot curled up under a tree. It wakes for a moment, waves, and dozes off again."))
        case 27: return WorldFind(kind: .relic, title: String(localized: "The calm compass"),
                                  detail: String(localized: "Its needle never points north. It points toward wherever you would feel most at peace."))
        case 28: return WorldFind(kind: .relic, title: String(localized: "A music box world"),
                                  detail: String(localized: "A tiny brass planet that plays a melody when you wind its equator."))
        case 29: return WorldFind(kind: .relic, title: String(localized: "A field of kites"),
                                  detail: String(localized: "Hundreds of kites tied to the ground, still flying after all these years."))
        case 30: return WorldFind(kind: .relic, title: String(localized: "The window to the sea"),
                                  detail: String(localized: "A window frame standing alone in the desert. Through it, the view is always of the ocean."))
        case 31: return WorldFind(kind: .relic, title: String(localized: "A forgotten telescope"),
                                  detail: String(localized: "It points at one exact spot in the sky. Look through it, and you see a small blue world."))
        case 32: return WorldFind(kind: .relic, title: String(localized: "The welcome stone"),
                                  detail: String(localized: "Carved with a single word that means both hello and rest."))
        case 33: return WorldFind(kind: .relic, title: String(localized: "Footprints of light"),
                                  detail: String(localized: "A trail of glowing footprints that leads to the best place to watch the sunrise."))

        // Phenomena
        case 34: return WorldFind(kind: .phenomenon, title: String(localized: "Upward rain"),
                                  detail: String(localized: "Rain falls upward here, slowly, and settles on the clouds."))
        case 35: return WorldFind(kind: .phenomenon, title: String(localized: "The listening hour"),
                                  detail: String(localized: "Once a day the whole planet goes quiet, as if it is listening for something."))
        case 36: return WorldFind(kind: .phenomenon, title: String(localized: "Slow lightning"),
                                  detail: String(localized: "Lightning takes almost a minute to cross the sky, so you can watch every branch unfold."))
        case 37: return WorldFind(kind: .phenomenon, title: String(localized: "The shy aurora"),
                                  detail: String(localized: "It only appears when nobody is looking straight at it."))
        case 38: return WorldFind(kind: .phenomenon, title: String(localized: "Floating lakes"),
                                  detail: String(localized: "Small round lakes drift through the air like soap bubbles, rippling in the breeze."))
        case 39: return WorldFind(kind: .phenomenon, title: String(localized: "Wandering shadows"),
                                  detail: String(localized: "Shadows here sometimes wander off on their own, and always come home by evening."))
        case 40: return WorldFind(kind: .phenomenon, title: String(localized: "The encore sunset"),
                                  detail: String(localized: "Once a year the sun sets, pauses, and rises again for a few more minutes of gold."))
        case 41: return WorldFind(kind: .phenomenon, title: String(localized: "Warm snow"),
                                  detail: String(localized: "The snowflakes here are warm, and they melt into tiny drops of light."))
        case 42: return WorldFind(kind: .phenomenon, title: String(localized: "Daylight stars"),
                                  detail: String(localized: "The air is so clear that the stars stay out all day, just a little paler."))
        case 43: return WorldFind(kind: .phenomenon, title: String(localized: "Gravity tides"),
                                  detail: String(localized: "Twice a day gravity softens, and everything loose floats up a few centimetres."))
        case 44: return WorldFind(kind: .phenomenon, title: String(localized: "The colour wind"),
                                  detail: String(localized: "A breeze that paints whatever it touches a new colour, then politely changes it back."))
        case 45: return WorldFind(kind: .phenomenon, title: String(localized: "Frozen music"),
                                  detail: String(localized: "The ice grows in the shape of sound waves, so every cave holds a song."))
        case 46: return WorldFind(kind: .phenomenon, title: String(localized: "Pocket nights"),
                                  detail: String(localized: "Small patches of night float across the daytime fields, each full of its own little stars."))
        case 47: return WorldFind(kind: .phenomenon, title: String(localized: "The long dusk"),
                                  detail: String(localized: "Dusk lasts a whole season here, and everything is painted in violet."))
        case 48: return WorldFind(kind: .phenomenon, title: String(localized: "The mirror sky"),
                                  detail: String(localized: "On still days the sky reflects the ground, and you can see yourself waving from above."))
        case 49: return WorldFind(kind: .phenomenon, title: String(localized: "Firefly meteors"),
                                  detail: String(localized: "Every evening, tiny shooting stars land in the grass and fade like fireflies."))
        default: return WorldFind(kind: .phenomenon, title: String(localized: "Pools of slow time"),
                                  detail: String(localized: "Time moves slower in the valleys. One hour there feels like a long, soft afternoon."))
        }
    }
}
