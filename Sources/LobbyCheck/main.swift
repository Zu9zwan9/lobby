import Foundation
import LobbyCore

// Support and CI path: prints what Lobby sees and what it would advise.
// Exit code 0 means nothing to do, 1 means the user needs to act.

let o = await Inspector.observe()
let r = diagnose(o)

print("""
      capport api      : \(o.capportAPI?.absoluteString ?? "-")
      capport captive  : \(o.capport.map { String($0.captive) } ?? "-")
      portal url       : \(o.capport?.userPortalURL?.absoluteString ?? "-")
      apple probe      : \(o.appleProbeSucceeded.map { $0 ? "Success" : "intercepted" } ?? "no answer")
      probe date skew  : \(o.appleProbeDateSkew.map { String(format: "%.0fs", $0) } ?? "-")
      gateway redirect : \(o.gatewayRedirect?.absoluteString ?? "-")
      dhcp dns         : \(o.dhcpDNS.joined(separator: ", "))
      effective dns    : \(o.effectiveDNS.joined(separator: ", "))
      tunnel primary   : \(o.tunnelOwnsDefaultRoute)
      private relay    : \(o.privateRelayEnabled)
      cna disabled     : \(o.captiveAssistantDisabled)

      \(r.advice.title)
      \(r.advice.detail)
      """)

exit(r.advice.needsAttention ? 1 : 0)
