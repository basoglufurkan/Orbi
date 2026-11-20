import Foundation

/// Every place a link can open in Lumora, from either form:
/// - `lumora://universe`, used by widgets, notifications and the app itself;
/// - `https://www.mobapptech.com/lumora/universe/`, the shareable form, which
///   messaging apps make tappable. With Lumora installed it opens the app
///   (universal link); otherwise the web page explains and offers the app.
///
/// Links only navigate. A focus link opens the setup screen with the length
/// and category filled in; nothing from a link starts a session or quiets apps
/// by itself.
enum DeepLink: Equatable, Sendable {
    enum Screen: String, CaseIterable, Sendable {
        case today, universe, odyssey, collection, insights
    }

    case screen(Screen)
    case yearInReview
    case settings
    case tasks
    /// Today's orbit: the day plan as a route.
    case plan
    /// The Habits sheet.
    case habits
    /// The Orbi+ paywall (nothing happens once Orbi+ is active).
    case plus
    /// The focus setup screen, optionally with a length and category.
    case focus(minutes: Int?, category: FocusCategory?)
    /// A friend's Focus together room.
    case join(code: String)

    static let scheme = "lumora"
    static let webHost = "www.mobapptech.com"
    /// Shareable links live under this path; the bare path is the landing page.
    static let webRoot = "/lumora/"
    /// The landing page: what Lumora is, and where to get it.
    static let landingPage = URL(string: "https://\(webHost)\(webRoot)")!

    /// Lengths a link may ask for, the same as the setup screen's custom range.
    static let minuteRange = 1...180

    // MARK: Parsing

    init?(url: URL) {
        var parts: [String]
        switch url.scheme?.lowercased() {
        case Self.scheme:
            parts = [url.host ?? ""] + url.pathComponents
        case "https", "http":
            guard url.host?.lowercased() == Self.webHost else { return nil }
            let path = url.pathComponents.filter { $0 != "/" }
            guard path.first?.lowercased() == "lumora" else { return nil }
            parts = Array(path.dropFirst())
        default:
            return nil
        }
        parts = parts.filter { !$0.isEmpty && $0 != "/" }.map { $0.lowercased() }
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name.lowercased(), $0) } },
            uniquingKeysWith: { first, _ in first })

        switch parts.first {
        case nil, "home":
            self = .screen(.today)
        case "year":
            self = .yearInReview
        case "insights" where parts.dropFirst().first == "year":
            self = .yearInReview
        case "settings":
            self = .settings
        case "tasks":
            self = .tasks
        case "plan", "orbit":
            self = .plan
        case "habits", "habit":
            self = .habits
        case "plus":
            self = .plus
        case "focus":
            let minutes = query["minutes"].flatMap(Int.init).map { min(max($0, Self.minuteRange.lowerBound), Self.minuteRange.upperBound) }
            let category = query["category"].flatMap { FocusCategory(rawValue: $0.lowercased()) }
            self = .focus(minutes: minutes, category: category)
        case "join", "together":
            // `lumora://together/CODE`, `/lumora/join/?code=CODE` or `/lumora/join/CODE`.
            let raw = query["code"] ?? parts.dropFirst().first ?? ""
            let code = TogetherCode.normalize(raw)
            guard TogetherCode.isValid(code) else { return nil }
            self = .join(code: code)
        case let name?:
            guard let screen = Screen(rawValue: name) else { return nil }
            self = .screen(screen)
        }
    }

    // MARK: Building

    /// The in-app form, for widgets and notifications.
    var appURL: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = segments.first
        components.path = segments.dropFirst().map { "/" + $0 }.joined()
        components.queryItems = queryItems
        return components.url!
    }

    /// The shareable form, for messages.
    var webURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.webHost
        components.path = Self.webRoot + segments.joined(separator: "/") + "/"
        components.queryItems = queryItems
        return components.url!
    }

    /// The link's path, for analytics ("focus", "insights/year"); never its code or query.
    var analyticsName: String { segments.joined(separator: "/") }

    private var segments: [String] {
        switch self {
        case let .screen(screen): [screen.rawValue]
        case .yearInReview: ["insights", "year"]
        case .settings: ["settings"]
        case .tasks: ["tasks"]
        case .plan: ["plan"]
        case .habits: ["habits"]
        case .plus: ["plus"]
        case .focus: ["focus"]
        case .join: ["join"]
        }
    }

    private var queryItems: [URLQueryItem]? {
        switch self {
        case let .focus(minutes, category):
            let items = [minutes.map { URLQueryItem(name: "minutes", value: String($0)) },
                         category.map { URLQueryItem(name: "category", value: $0.rawValue) }].compactMap { $0 }
            return items.isEmpty ? nil : items
        case let .join(code):
            return [URLQueryItem(name: "code", value: code)]
        default:
            return nil
        }
    }
}

/// Room codes: six characters with no 0/O or 1/I/L, so a code read aloud is
/// never ambiguous.
enum TogetherCode {
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static let length = 6

    /// Tidies what someone typed: uppercase, no spaces or dashes.
    static func normalize(_ raw: String) -> String {
        String(raw.uppercased().filter { alphabet.contains($0) }.prefix(length))
    }

    static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy { alphabet.contains($0) }
    }
}
