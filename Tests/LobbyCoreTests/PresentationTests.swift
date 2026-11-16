import XCTest
@testable import LobbyCore

/// Acceptance tests for what the menu bar shows. Each test reads as
/// Given (what Lobby diagnosed) / When (the menu renders it) / Then (what the person sees).
final class PresentationTests: XCTestCase {

    private let portal = URL(string: "https://wifi.example.com/login")!

    private var everyRecommendation: [Recommendation] {
        [
            .connected,
            .openPortal(portal, why: .capportAPI),
            .openPortal(portal, why: .gatewayRedirect),
            .disconnectVPN,
            .restoreNetworkDNS(inUse: ["8.8.8.8"], offered: ["192.168.1.1"]),
            .setPublicDNS,
            .disablePrivateRelay,
            .reenableCaptiveAssistant,
            .openNeverSSL,
            .undetermined,
        ]
    }

    // Scenario: the network is open.
    func testGivenConnected_ThenNothingAsksForAttention() {
        let advice = Recommendation.connected.advice
        XCTAssertFalse(advice.needsAttention)
        XCTAssertEqual(advice.action, .none)
        XCTAssertNil(advice.actionTitle)
    }

    // Scenario: every problem state is flagged; only "connected" is calm.
    func testGivenAnyProblem_ThenTheMenuBarNeedsAttention() {
        for rec in everyRecommendation where rec != .connected {
            XCTAssertTrue(rec.advice.needsAttention, "\(rec) should need attention")
        }
    }

    // Rule: a button appears exactly when there is something to do.
    func testButtonAppearsOnlyWhenThereIsAnAction() {
        for rec in everyRecommendation {
            let advice = rec.advice
            XCTAssertEqual(advice.actionTitle == nil, advice.action == .none,
                           "\(rec): button label and action disagree")
        }
    }

    // Rule: plain language. Every state has a title and an explanation.
    func testEveryStateExplainsItselfInWords() {
        for rec in everyRecommendation {
            XCTAssertFalse(rec.advice.title.isEmpty, "\(rec) has no title")
            XCTAssertFalse(rec.advice.detail.isEmpty, "\(rec) has no detail")
        }
    }

    // Scenario: the network announces its portal (RFC 8908).
    func testGivenPortalFound_WhenOpened_ThenItOpensThatExactPage() {
        let advice = Recommendation.openPortal(portal, why: .capportAPI).advice
        XCTAssertEqual(advice.title, "Sign-in page found")
        XCTAssertEqual(advice.action, .open(portal))
        XCTAssertEqual(advice.actionTitle, "Open sign-in page")
    }

    // Scenario: the two ways of finding a portal are explained differently.
    func testPortalEvidenceChangesTheExplanation() {
        let capport = Recommendation.openPortal(portal, why: .capportAPI).advice.detail
        let redirect = Recommendation.openPortal(portal, why: .gatewayRedirect).advice.detail
        XCTAssertNotEqual(capport, redirect)
    }

    // Scenario: custom DNS hides the portal. The advice names both sides
    // and warns against the usual bad fix.
    func testGivenOverriddenDNS_ThenAdviceNamesBothServersAndWarnsAgainst8888() {
        let advice = Recommendation
            .restoreNetworkDNS(inUse: ["1.1.1.1", "9.9.9.9"], offered: ["10.0.0.1"])
            .advice
        XCTAssertTrue(advice.detail.contains("1.1.1.1, 9.9.9.9"))
        XCTAssertTrue(advice.detail.contains("10.0.0.1"))
        XCTAssertTrue(advice.detail.contains("Do not set 8.8.8.8"))
        XCTAssertEqual(advice.action, .openSettings(.network))
    }

    // Scenario: Private Relay blocks the portal. Its switch lives in Apple Account.
    func testGivenPrivateRelay_ThenItOpensAppleAccountSettings() {
        XCTAssertEqual(Recommendation.disablePrivateRelay.advice.action,
                       .openSettings(.appleAccount))
    }

    // Scenario: a portal exists but has no known address. Only plain HTTP
    // gets intercepted by a portal, so the fallback page must not be HTTPS.
    func testGivenUnknownPortalAddress_ThenFallbackPageIsPlainHTTP() {
        guard case let .open(url) = Recommendation.openNeverSSL.advice.action else {
            return XCTFail("expected an .open action")
        }
        XCTAssertEqual(url.scheme, "http")
    }

    // Rule: Lobby never edits settings. It can only open a page or a pane.
    func testSettingsLinksUseTheSystemSettingsScheme() {
        for pane in [SettingsPane.network, .appleAccount] {
            XCTAssertEqual(pane.url.scheme, "x-apple.systempreferences")
            XCTAssertTrue(pane.url.absoluteString.hasSuffix(pane.rawValue))
        }
    }
}
