import Foundation

/// What the menu bar offers to do. The app performs these; it never edits settings.
public enum LobbyAction: Sendable, Equatable {
    case open(URL)
    case openSettings(SettingsPane)
    case none
}

/// Deep links into System Settings. These identifiers move between macOS
/// releases, so `SettingsPane.url` is the single place to fix when one breaks.
public enum SettingsPane: String, Sendable, Equatable {
    case network = "com.apple.Network-Settings.extension"
    case appleAccount = "com.apple.systempreferences.AppleIDSettings"

    public var url: URL { URL(string: "x-apple.systempreferences:\(rawValue)")! }
}

/// Plain-language presentation of a recommendation. No jargon, no findings list.
public struct Advice: Sendable, Equatable {
    public let title: String
    public let detail: String
    public let actionTitle: String?
    public let action: LobbyAction
    public let needsAttention: Bool
}

public extension Recommendation {
    var advice: Advice {
        switch self {
        case .connected:
            return Advice(title: "You're online",
                          detail: "This network isn't asking you to sign in.",
                          actionTitle: nil, action: .none, needsAttention: false)

        case let .openPortal(url, why):
            let detail: String
            switch why {
            case .capportAPI:
                detail = "This network says you still need to sign in, even though macOS thinks you're already online."
            case .gatewayRedirect:
                detail = "The router is sending every page to a sign-in screen. macOS didn't show it to you."
            case .forgedProbe:
                detail = "The network told macOS you were online when you weren't. Here's the real sign-in page."
            }
            return Advice(title: "Sign-in page found", detail: detail,
                          actionTitle: "Open sign-in page", action: .open(url),
                          needsAttention: true)

        case .disconnectVPN:
            return Advice(title: "Turn off your VPN first",
                          detail: "Your VPN is carrying all traffic, so the sign-in page can't load. Turn it off, sign in, then turn it back on.",
                          actionTitle: nil, action: .none, needsAttention: true)

        case let .restoreNetworkDNS(inUse, offered):
            return Advice(
                title: "Your Mac is using a different DNS service",
                detail: "You're set to \(inUse.joined(separator: ", ")), but this network needs \(offered.joined(separator: ", ")) to show its sign-in page. Switch DNS back to automatic for now. Do not set 8.8.8.8 here, that makes it worse.",
                actionTitle: "Open Network settings",
                action: .openSettings(.network), needsAttention: true)

        case .setPublicDNS:
            return Advice(
                title: "This network didn't give you a DNS server",
                detail: "Nothing can load until you set one. In Wi-Fi details, add 1.1.1.1 under DNS.",
                actionTitle: "Open Network settings",
                action: .openSettings(.network), needsAttention: true)

        case .disablePrivateRelay:
            return Advice(
                title: "iCloud Private Relay is blocking the sign-in page",
                detail: "Turn it off, sign in to the Wi-Fi, then turn it back on.",
                actionTitle: "Open Apple Account settings",
                action: .openSettings(.appleAccount), needsAttention: true)

        case .reenableCaptiveAssistant:
            return Advice(
                title: "Wi-Fi sign-in pages are switched off on this Mac",
                detail: "Someone disabled the feature that shows Wi-Fi login screens. Lobby can still find them, but macOS won't show them on its own.",
                actionTitle: nil, action: .none, needsAttention: true)

        case .openNeverSSL:
            return Advice(
                title: "There's probably a sign-in page",
                detail: "We couldn't find its address. Opening a plain page usually forces it to appear.",
                actionTitle: "Try to force it open",
                action: .open(URL(string: "http://neverssl.com")!), needsAttention: true)

        case .undetermined:
            return Advice(
                title: "Couldn't work out what's wrong",
                detail: "Wi-Fi is connected but something is blocking pages, and none of the usual causes match. Copy the details and open an issue if this keeps happening.",
                actionTitle: nil, action: .none, needsAttention: true)
        }
    }
}
