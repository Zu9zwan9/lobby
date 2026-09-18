import Foundation

/// Everything Lobby can observe without root. Pure data, no I/O.
public struct Observations: Sendable, Equatable {
    /// DHCP option 114 (RFC 8910). The CAPPORT API endpoint, not the human page.
    public var capportAPI: URL?
    /// Parsed RFC 8908 response from `capportAPI`, if the fetch succeeded.
    public var capport: CapportStatus?
    /// Apple's probe returned the literal success body. nil means the probe failed.
    public var appleProbeSucceeded: Bool?
    /// Seconds between the probe response's `Date:` header and a known-live clock.
    /// Large values mean the success page was served from a stale cache, i.e. forged.
    public var appleProbeDateSkew: TimeInterval?
    /// Where http://<gateway>/ redirected us, if anywhere.
    public var gatewayRedirect: URL?
    /// Resolvers the DHCP lease offered (option 6).
    public var dhcpDNS: [String] = []
    /// Resolvers macOS is actually using.
    public var effectiveDNS: [String] = []
    /// The primary interface is a tunnel, so a VPN owns the default route.
    public var tunnelOwnsDefaultRoute = false
    /// iCloud Private Relay is enabled system-wide.
    public var privateRelayEnabled = false
    /// The Wi-Fi MAC has the locally-administered bit set, so it is randomized.
    public var macIsRandomized = false
    /// Captive network support was switched off in com.apple.captive.control.
    public var captiveAssistantDisabled = false

    public init() {}
}

/// RFC 8908 Captive Portal API response.
public struct CapportStatus: Sendable, Equatable, Decodable {
    public let captive: Bool
    public let userPortalURL: URL?
    public let venueInfoURL: URL?
    public let secondsRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case captive
        case userPortalURL = "user-portal-url"
        case venueInfoURL = "venue-info-url"
        case secondsRemaining = "seconds-remaining"
    }

    public init(captive: Bool, userPortalURL: URL? = nil,
                venueInfoURL: URL? = nil, secondsRemaining: Int? = nil) {
        self.captive = captive
        self.userPortalURL = userPortalURL
        self.venueInfoURL = venueInfoURL
        self.secondsRemaining = secondsRemaining
    }
}

/// Exactly one next step, in the user's terms. Never a list of findings.
public enum Recommendation: Sendable, Equatable {
    /// Nothing to do.
    case connected
    /// A login page exists. `why` explains how we found it when macOS did not.
    case openPortal(URL, why: PortalEvidence)
    /// A tunnel owns the default route and will block the login page.
    case disconnectVPN
    /// DNS is overridden, so the gateway can never redirect us. Cause B.
    case restoreNetworkDNS(inUse: [String], offered: [String])
    /// The lease carries no usable resolver. Cause A. The opposite fix.
    case setPublicDNS
    /// Private Relay is on and is the most likely remaining blocker.
    case disablePrivateRelay
    /// Captive network support was switched off on this Mac.
    case reenableCaptiveAssistant
    /// A portal exists but we could not find its address.
    case openNeverSSL
    /// We could not tell. Say so rather than guess.
    case undetermined
}

/// Why we believe a portal exists when macOS says otherwise.
public enum PortalEvidence: Sendable, Equatable {
    /// The CAPPORT API said `captive: true`. Deterministic, no inference.
    case capportAPI
    /// The gateway redirected a plain HTTP request to a login page.
    case gatewayRedirect
    /// Apple's probe reported success from a stale cache. Corroborating only.
    case forgedProbe(skewSeconds: TimeInterval)
}

/// Skew beyond this means the probe response came from a cache, not from Apple.
/// Chosen well above ordinary CDN freshness so legitimate caching never trips it.
public let forgedProbeThreshold: TimeInterval = 3600

/// The only non-trivial logic in Lobby. Pure, total, ordered by confidence:
/// deterministic evidence first, inference last, "I don't know" before a guess.
public func diagnose(_ o: Observations) -> Recommendation {
    // 1. The network told us directly. Nothing beats this.
    if let c = o.capport, c.captive, let portal = c.userPortalURL {
        return .openPortal(portal, why: .capportAPI)
    }

    // 2. The network told us it is open, and nothing contradicts it.
    if let c = o.capport, !c.captive, o.gatewayRedirect == nil {
        return .connected
    }

    // 3. A tunnel swallows every probe below, so rule it out before inferring.
    if o.tunnelOwnsDefaultRoute { return .disconnectVPN }

    // 4. Cause B. We resolve somewhere the gateway cannot intercept, so it can
    //    never redirect us. Note this is checked BEFORE cause A: setting a public
    //    resolver here is the popular advice and it makes things worse.
    if !o.dhcpDNS.isEmpty, !o.effectiveDNS.isEmpty,
       Set(o.effectiveDNS).isDisjoint(with: Set(o.dhcpDNS)) {
        return .restoreNetworkDNS(inUse: o.effectiveDNS, offered: o.dhcpDNS)
    }

    // 5. Cause A. The lease offered nothing to resolve with. Opposite fix.
    if o.dhcpDNS.isEmpty, o.effectiveDNS.isEmpty { return .setPublicDNS }

    // 6. The gateway is redirecting, so a portal exists whatever the probe claims.
    if let redirect = o.gatewayRedirect {
        return .openPortal(redirect, why: .gatewayRedirect)
    }

    // 7. This Mac cannot show portals at all until captive support is back on.
    if o.captiveAssistantDisabled { return .reenableCaptiveAssistant }

    // 8. The probe "succeeded" from a stale cache and we have no portal address.
    //    Corroborating evidence only, which is why it sits below everything above.
    if o.appleProbeSucceeded == true,
       let skew = o.appleProbeDateSkew, skew > forgedProbeThreshold {
        return .openNeverSSL
    }

    // 9. The probe never came back. Something is eating it.
    if o.appleProbeSucceeded == nil {
        if o.privateRelayEnabled { return .disablePrivateRelay }
        return .openNeverSSL
    }

    // A randomized MAC is recorded in Observations for support output, but it is
    // deliberately NOT a recommendation: Lobby cannot tell whether a given portal
    // binds sessions to the MAC, so advising on it would nag every user on every
    // network. Revisit when we track repeat portal hits per SSID.

    if o.appleProbeSucceeded == true { return .connected }
    return .undetermined
}
