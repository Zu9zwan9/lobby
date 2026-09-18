import XCTest
@testable import LobbyCore

final class DiagnosisTests: XCTestCase {

    private func obs(_ build: (inout Observations) -> Void) -> Observations {
        var o = Observations()
        build(&o)
        return o
    }

    // The deterministic path. Nothing outranks the network answering directly.
    func testCapportCaptiveWins() {
        let portal = URL(string: "https://wifi.example.com")!
        let o = obs {
            $0.capport = CapportStatus(captive: true, userPortalURL: portal)
            $0.tunnelOwnsDefaultRoute = true      // would otherwise fire
            $0.privateRelayEnabled = true          // would otherwise fire
        }
        XCTAssertEqual(diagnose(o), .openPortal(portal, why: .capportAPI))
    }

    func testCapportOpenNetworkIsConnected() {
        let o = obs { $0.capport = CapportStatus(captive: false) }
        XCTAssertEqual(diagnose(o), .connected)
    }

    // A tunnel swallows every probe below it, so it must be ruled out first.
    func testVPNBeatsInference() {
        let o = obs {
            $0.tunnelOwnsDefaultRoute = true
            $0.dhcpDNS = ["10.1.0.1"]
            $0.effectiveDNS = ["1.1.1.1"]
        }
        XCTAssertEqual(diagnose(o), .disconnectVPN)
    }

    // The correctness case this whole tool exists for: an override is present,
    // and the popular advice (set a public resolver) is exactly wrong here.
    func testDNSOverrideIsDetected() {
        let o = obs {
            $0.dhcpDNS = ["10.1.0.1"]
            $0.effectiveDNS = ["45.90.28.0", "45.90.30.0"]
        }
        XCTAssertEqual(diagnose(o),
                       .restoreNetworkDNS(inUse: ["45.90.28.0", "45.90.30.0"],
                                          offered: ["10.1.0.1"]))
    }

    // The opposite case, same symptom, opposite fix.
    func testNoDNSAtAllAsksForPublicResolver() {
        XCTAssertEqual(diagnose(obs { _ in }), .setPublicDNS)
    }

    // Overlapping resolvers are not an override, they are normal.
    func testMatchingDNSIsNotAnOverride() {
        let o = obs {
            $0.dhcpDNS = ["10.1.0.1"]
            $0.effectiveDNS = ["10.1.0.1"]
            $0.appleProbeSucceeded = true
        }
        XCTAssertEqual(diagnose(o), .connected)
    }

    // WestJet, 2026-09-18, 35,000 feet: probe says Success, gateway redirects anyway.
    func testGatewayRedirectBeatsASuccessfulProbe() {
        let portal = URL(string: "https://wifi.westjet.com/")!
        let o = obs {
            $0.appleProbeSucceeded = true
            $0.dhcpDNS = ["10.1.0.1"]
            $0.effectiveDNS = ["10.1.0.1"]
            $0.gatewayRedirect = portal
        }
        XCTAssertEqual(diagnose(o), .openPortal(portal, why: .gatewayRedirect))
    }

    // A stale Date proves nothing on its own, so it only fires with no portal URL.
    func testForgedProbeWithoutAnAddressFallsBackToNeverSSL() {
        let o = obs {
            $0.appleProbeSucceeded = true
            $0.appleProbeDateSkew = 19 * 3600
            $0.dhcpDNS = ["10.1.0.1"]
            $0.effectiveDNS = ["10.1.0.1"]
        }
        XCTAssertEqual(diagnose(o), .openNeverSSL)
    }

    func testFreshProbeIsNotTreatedAsForged() {
        let o = obs {
            $0.appleProbeSucceeded = true
            $0.appleProbeDateSkew = 4
            $0.dhcpDNS = ["10.1.0.1"]
            $0.effectiveDNS = ["10.1.0.1"]
        }
        XCTAssertEqual(diagnose(o), .connected)
    }

    func testSilentProbeWithPrivateRelayBlamesPrivateRelay() {
        let o = obs {
            $0.appleProbeSucceeded = nil
            $0.privateRelayEnabled = true
            $0.dhcpDNS = ["10.1.0.1"]
            $0.effectiveDNS = ["10.1.0.1"]
        }
        XCTAssertEqual(diagnose(o), .disablePrivateRelay)
    }

    // Byte-for-byte what the aircraft's Starlink router returned.
    func testDecodesRealCapportResponse() throws {
        let json = """
        {"can-extend-session":true,"captive":false,
         "user-portal-url":"https://wifi.westjet.com",
         "venue-info-url":"https://wifi.westjet.com"}
        """.data(using: .utf8)!
        let status = try JSONDecoder().decode(CapportStatus.self, from: json)
        XCTAssertFalse(status.captive)
        XCTAssertEqual(status.userPortalURL?.absoluteString, "https://wifi.westjet.com")
        XCTAssertNil(status.secondsRemaining)
    }

    // Every recommendation must produce something a non-technical user can act on.
    func testEveryRecommendationHasPlainLanguage() {
        let all: [Recommendation] = [
            .connected,
            .openPortal(URL(string: "https://e.com")!, why: .capportAPI),
            .disconnectVPN,
            .restoreNetworkDNS(inUse: ["1.1.1.1"], offered: ["10.0.0.1"]),
            .setPublicDNS, .disablePrivateRelay, .reenableCaptiveAssistant,
            .openNeverSSL, .undetermined,
        ]
        for r in all {
            XCTAssertFalse(r.advice.title.isEmpty, "\(r) has no title")
            XCTAssertFalse(r.advice.detail.isEmpty, "\(r) has no detail")
        }
    }
}
