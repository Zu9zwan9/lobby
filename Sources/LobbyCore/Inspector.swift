import Foundation

/// Performs the network probes and assembles `Observations`.
/// Ordered so the deterministic CAPPORT path runs first: on macOS 15+ a request
/// to a private gateway address triggers the Local Network permission prompt, and
/// there is no reason to spend that prompt when the network already answered us.
public enum Inspector {

    public static let appleProbe = URL(string: "http://captive.apple.com/hotspot-detect.html")!
    private static let expectedProbeBody = "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>"

    private static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.timeoutIntervalForRequest = 8
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }

    private struct Fetch {
        let body: String
        let finalURL: URL?
        let serverDate: Date?
    }

    /// RFC 9110 date format. DateFormatter is expensive to build, and this runs
    /// on every network change, so it is created once.
    private static let httpDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    private static func fetch(_ url: URL, accept: String? = nil) async -> Fetch? {
        var req = URLRequest(url: url)
        if let accept { req.setValue(accept, forHTTPHeaderField: "Accept") }
        guard let (data, response) = try? await session().data(for: req),
              let http = response as? HTTPURLResponse else { return nil }
        return Fetch(body: String(data: data.prefix(4096), encoding: .utf8) ?? "",
                     finalURL: http.url,
                     serverDate: http.value(forHTTPHeaderField: "Date")
                         .flatMap(httpDate.date(from:)))
    }

    /// Gather everything, cheapest and most definitive first.
    public static func observe(now: Date = Date()) async -> Observations {
        var o = Observations()

        o.dhcpDNS = NetworkState.dhcpDNS()
        o.effectiveDNS = NetworkState.effectiveDNS()
        o.tunnelOwnsDefaultRoute = NetworkState.tunnelOwnsDefaultRoute()
        o.privateRelayEnabled = NetworkState.privateRelayEnabled()
        o.captiveAssistantDisabled = NetworkState.captiveAssistantDisabled()
        o.capportAPI = NetworkState.capportAPI()

        // 1. Ask the network directly. Public hostname in practice, so no Local
        //    Network permission is needed for this path.
        var liveClock: Date?
        if let api = o.capportAPI,
           let r = await fetch(api, accept: "application/captive+json") {
            liveClock = r.serverDate
            if let data = r.body.data(using: .utf8) {
                o.capport = try? JSONDecoder().decode(CapportStatus.self, from: data)
            }
        }

        // A definitive "you are captive" needs nothing further.
        if o.capport?.captive == true, o.capport?.userPortalURL != nil { return o }

        // 2. Apple's own probe, so we can catch it lying.
        if let r = await fetch(appleProbe) {
            o.appleProbeSucceeded = r.body.contains(expectedProbeBody)
            if let served = r.serverDate {
                // Prefer a response we know is live; fall back to the system clock,
                // which is itself suspect on a machine that has been asleep.
                o.appleProbeDateSkew = abs((liveClock ?? now).timeIntervalSince(served))
            }
        }

        // 3. Only now spend the Local Network prompt.
        if o.capport == nil || o.appleProbeSucceeded != true {
            if let gw = NetworkState.router(), let url = URL(string: "http://\(gw)/"),
               let r = await fetch(url), let final = r.finalURL,
               final.host != gw {
                o.gatewayRedirect = final
            }
        }

        return o
    }

    /// One call for the app: observe, then decide.
    public static func check(now: Date = Date()) async -> Recommendation {
        diagnose(await observe(now: now))
    }
}
