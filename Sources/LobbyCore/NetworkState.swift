import Foundation
import SystemConfiguration
// The DHCP accessors live in an EXPLICIT submodule. A plain `import
// SystemConfiguration` compiles but leaves them out of scope, with an error that
// reads like the framework is missing. This line is load-bearing.
import SystemConfiguration.SCDynamicStoreCopyDHCPInfo

/// Read-only view of what macOS currently believes about the network.
/// Every call here is unprivileged and side-effect free.
public enum NetworkState {

    // MARK: DHCP lease

    private static func lease() -> CFDictionary? {
        SCDynamicStoreCopyDHCPInfo(nil, nil)
    }

    private static func option(_ info: CFDictionary, _ code: UInt8) -> Data? {
        DHCPInfoGetOptionData(info, code) as Data?
    }

    /// DHCP option 114 (RFC 8910): the CAPPORT API endpoint.
    public static func capportAPI() -> URL? {
        guard let info = lease(), let d = option(info, 114),
              let s = String(data: d, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)),
              !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// DHCP option 6: the resolvers this network offered us.
    public static func dhcpDNS() -> [String] {
        guard let info = lease(), let d = option(info, 6) else { return [] }
        return stride(from: 0, to: d.count - d.count % 4, by: 4).map {
            "\(d[$0]).\(d[$0 + 1]).\(d[$0 + 2]).\(d[$0 + 3])"
        }
    }

    /// DHCP option 3: the default gateway.
    public static func router() -> String? {
        guard let info = lease(), let d = option(info, 3), d.count >= 4 else { return nil }
        return "\(d[0]).\(d[1]).\(d[2]).\(d[3])"
    }

    // MARK: Effective configuration

    private static func global(_ entity: String) -> [String: Any]? {
        let key = "State:/Network/Global/\(entity)" as CFString
        return SCDynamicStoreCopyValue(nil, key) as? [String: Any]
    }

    /// The resolvers macOS is actually using, whatever DHCP offered.
    public static func effectiveDNS() -> [String] {
        global("DNS")?["ServerAddresses"] as? [String] ?? []
    }

    /// The interface carrying the default route, e.g. "en0" or "utun4".
    public static func primaryInterface() -> String? {
        global("IPv4")?["PrimaryInterface"] as? String
    }

    /// True when a tunnel owns the default route. Private Relay creates utun
    /// interfaces too, but does not become the primary interface, so it is not
    /// caught here by accident.
    public static func tunnelOwnsDefaultRoute() -> Bool {
        guard let i = primaryInterface() else { return false }
        return ["utun", "ipsec", "ppp", "tap", "tun"].contains { i.hasPrefix($0) }
    }

    // MARK: Wi-Fi address

    /// True when the MAC in use has the locally-administered bit set, which is
    /// what macOS does for a Private Wi-Fi Address. Reading the per-SSID setting
    /// itself needs root; observing its effect does not.
    public static func macIsRandomized(interface: String? = nil) -> Bool {
        guard let want = interface ?? primaryInterface() else { return false }
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let start = head else { return false }
        defer { freeifaddrs(head) }

        for ptr in sequence(first: start, next: { $0.pointee.ifa_next }) {
            guard String(cString: ptr.pointee.ifa_name) == want,
                  let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let dl = UnsafeRawPointer(addr).assumingMemoryBound(to: sockaddr_dl.self)
            guard dl.pointee.sdl_alen == 6 else { continue }
            let first = withUnsafeBytes(of: dl.pointee.sdl_data) { raw -> UInt8 in
                raw[Int(dl.pointee.sdl_nlen)]
            }
            return first & 0x02 != 0
        }
        return false
    }

    // MARK: Privacy and captive settings

    /// iCloud Private Relay, system-wide. The per-network "Limit IP Address
    /// Tracking" toggle lives in a root-only plist and is deliberately not read.
    public static func privateRelayEnabled() -> Bool {
        guard let defaults = UserDefaults(suiteName: "com.apple.networkserviceproxy"),
              let blob = defaults.data(forKey: "NSPServiceStatusManagerInfo"),
              let plist = try? PropertyListSerialization.propertyList(
                  from: blob, options: [], format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any] else { return false }

        for object in objects {
            if let dict = object as? [String: Any],
               let status = dict["PrivacyProxyServiceStatus"] as? Int {
                return status == 1
            }
        }
        return false
    }

    /// Some hardening guides switch captive network support off entirely and the
    /// user forgets. Cheap to check, and it explains an otherwise baffling Mac.
    public static func captiveAssistantDisabled() -> Bool {
        let path = "/Library/Preferences/SystemConfiguration/com.apple.captive.control.plist"
        guard let d = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(
                  from: d, options: [], format: nil) as? [String: Any],
              let active = plist["Active"] as? Bool else { return false }
        return active == false
    }
}
