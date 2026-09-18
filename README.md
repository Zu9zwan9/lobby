# Lobby

Your Mac says the Wi-Fi is connected. Nothing loads. No login page appears.

Lobby finds the login page and hands it to you.

![menu bar screenshot placeholder](docs/screenshot.png)

## The bug, captured at 35,000 feet

On a WestJet flight in September 2026, macOS reported a healthy connection and
refused to show a login page. The login address was sitting in the DHCP lease
the whole time:

```
option 114 (captive portal): https://wifi.westjet.com/starlinkrouter/captive-portal
option 6  (dns)            : 10.1.0.1
option 3  (router)         : 10.1.0.1
```

macOS has supported that option, the CAPPORT standard ([RFC 8908] and
[RFC 8910]), since Big Sur. It read it and threw it away, because the same
router answered Apple's detection probe with `Success`.

Then we looked at when that success page was actually made:

```
APPLE-PROBE  date: Fri, 18 Sep 2026 04:09:37 GMT
CAPPORT-API  date: Fri, 18 Sep 2026 23:16:23 GMT
```

The aircraft's walled garden was serving a **cached copy of Apple's success
page**, captured roughly 19 hours earlier when the plane was last on the ground.
macOS was not told the truth. It was handed a souvenir.

Lobby asks the network directly instead of trusting the souvenir.

## What it does

It sits in the menu bar. When you join a network, it checks, and if there is
something to do it tells you in one sentence with one button.

It does not open browser windows by itself. It does not change your settings.
It tells you what is wrong and, where macOS allows, opens the right Settings
pane so you can decide.

## The thing everyone gets backwards

Two completely different problems produce the identical symptom, and they need
**opposite** fixes:

| What is actually wrong | The correct fix |
|---|---|
| The network handed you no DNS server at all | Set a public resolver such as 1.1.1.1 |
| You are already using a DNS server the network cannot intercept | Put DNS back to automatic |

The second case covers DNS-over-HTTPS profiles, NextDNS, Cloudflare WARP,
AdGuard, Pi-hole and corporate filtering agents. It is the better-evidenced of
the two by a wide margin: DNSFilter, Cisco Umbrella, NextDNS and AdGuard all
ship documentation or product features for it.

Nearly every guide on the internet tells you to set 8.8.8.8. In the more common
case, that makes things worse.

Lobby compares what DHCP offered against what your Mac is actually using, and
tells you which of the two opposite actions applies.

## What it checks

All of it unprivileged, none of it with root:

- DHCP option 114, then the CAPPORT API response, which is deterministic
- Apple's probe, including whether its `Date` header proves a stale cache
- Whether the router redirects plain HTTP to a login page
- DNS offered by DHCP against DNS actually in effect
- Whether a VPN tunnel owns the default route
- Whether iCloud Private Relay is on
- Whether captive network support was switched off on this Mac

## What it will not do

- Log you in. It finds the page, you decide what to type.
- Store credentials.
- Change a network setting on your behalf.
- Claim a cause it cannot prove. When it does not know, it says so.

## Install

Download the latest `.dmg` from [Releases](../../releases), drag Lobby to
Applications, open it. It is signed and notarized.

## Command line

```
swift run -c release LobbyCheck
```

Prints everything Lobby sees and what it would advise. Exit code 1 means action
is needed. Useful for bug reports.

## Building

```
make test      # run the decision-table tests
make app       # assemble Lobby.app
make check     # diagnose the network you are on right now
```

## How it works, and why this is harder than it looks

Apple states there is no public API for determining whether a network is
captive. `NEHotspotHelper` does not exist on macOS, and
`CNCopySupportedInterfaces` returns null. Everything here is inference from
observable state, ordered so that deterministic evidence always outranks
guessing, and so that "I don't know" outranks a confident wrong answer.

The decision logic is one pure function in
[`Diagnosis.swift`](Sources/LobbyCore/Diagnosis.swift) with no I/O, and it is
the only thing in this project with real complexity. Read that file first.

One implementation note that cost an afternoon: the DHCP accessors live in an
**explicit** submodule. `import SystemConfiguration` compiles fine and leaves
them out of scope.

```swift
import SystemConfiguration.SCDynamicStoreCopyDHCPInfo
```

## Prior art

[captive-browser](https://github.com/FiloSottile/captive-browser) by Filippo
Valsorda solves the DNS-override case well, as a Go CLI with a config file.
Lobby covers more causes and is built for people who will never open a terminal.

## License

MIT

[RFC 8908]: https://datatracker.ietf.org/doc/html/rfc8908
[RFC 8910]: https://datatracker.ietf.org/doc/html/rfc8910
