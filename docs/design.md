# Lobby design record

2026-09-18. Written on a WestJet flight, against the network that caused it.

## Problem

macOS silently fails to show captive portal login pages. The failure has at
least twelve distinct causes. The user sees one symptom: connected Wi-Fi, no
internet, no login page.

## Constraint that shapes everything

Apple states there is no public API to determine whether a network is captive.
`NEHotspotHelper` does not exist on macOS. `CNCopySupportedInterfaces` returns
null. Every answer must be inferred from observable, unprivileged state.

Source: Apple DTS in developer forum threads 747798, 739758, 703189.

## Decisions

**Menu bar app, not a CLI.** The audience is people who will never open a
terminal. A `LobbyCheck` CLI exists for bug reports and CI, not as the product.

**One recommendation, never a findings list.** A non-technical user handed eight
diagnostics is worse off than before. `diagnose()` returns exactly one next step.

**Deterministic evidence outranks inference; inference outranks guessing; "I
don't know" outranks a confident wrong answer.** This is the rule ordering in
`Diagnosis.swift` and the reason it is a single pure function.

**Open portals in Safari explicitly.** Chrome's HTTPS-First, Firefox's
HTTPS-Only and HSTS pinning rewrite the plain-HTTP redirect many portals rely
on. One line of code removes that entire failure class without a single check.

**Never mutate settings.** Lobby explains and deep-links to the right Settings
pane. Changing network configuration on someone's machine without consent is
how a utility earns a support queue.

**CAPPORT before gateway probing.** On macOS 15+ a request to a private gateway
address triggers the Local Network permission prompt. The CAPPORT endpoint is a
public host in practice, so the deterministic path costs no prompt. Spend the
prompt only when the deterministic path fails.

## Verified on live hardware, not assumed

1. `SCDynamicStoreCopyDHCPInfo` returns option 114 on a live captive network.
   It requires `import SystemConfiguration.SCDynamicStoreCopyDHCPInfo`, an
   explicit submodule; the umbrella import compiles and omits the symbols.
2. Starlink's aviation router implements RFC 8908 correctly, serving
   `application/captive+json` with `captive` and `user-portal-url`.
3. The portal hostname resolves to a public address, so the main path needs no
   Local Network permission.
4. Apple's probe was answered from a cache 41,691 seconds stale. Measurable.

## Rejected

**Per-SSID settings.** "Limit IP Address Tracking" and Private Wi-Fi Address
mode live in a root-only plist. Lobby observes effects instead of reading
settings, or says nothing.

**MAC randomization advice.** Removed after the live run proved it unreachable
behind the CAPPORT short-circuit, and unfixable if reordered: Lobby cannot tell
whether a portal binds sessions to the MAC, so the advice would nag every user
on every network. Revisit when repeat portal hits per SSID are tracked.

**Security-agent detection.** `systemextensionsctl list` proves presence, never
causation. Not worth an accusation we cannot support.

**Auto-login and session keepalive.** A different product with a different
support burden.

## Open risks

- Settings deep-link identifiers change between macOS releases.
  `SettingsPane.url` is the single place to fix them.
- Local Network permission is reported to sometimes need a reboot or reset
  after OS updates. The gateway fallback must degrade quietly when denied.
- The stale-`Date` heuristic could in principle fire on an unusual CDN cache.
  It is ranked below every other signal and never decides alone.
