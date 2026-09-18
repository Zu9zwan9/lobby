import SwiftUI
import Network
import ServiceManagement
import UserNotifications
import LobbyCore

@main
struct LobbyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.advice.needsAttention
                  ? "wifi.exclamationmark" : "wifi")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var advice: Advice = Recommendation.connected.advice
    private(set) var checking = false
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register()
                          : SMAppService.mainApp.unregister()
        }
    }

    private let monitor = NWPathMonitor()
    private var lastNotified: String?

    init() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert]) { _, _ in }

        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                // Let DHCP settle before reading the lease.
                try? await Task.sleep(for: .seconds(3))
                await self?.check(notify: true)
            }
        }
        monitor.start(queue: .global(qos: .utility))
        Task { await check(notify: false) }
    }

    func check(notify: Bool) async {
        checking = true
        defer { checking = false }
        let recommendation = await Inspector.check()
        advice = recommendation.advice
        guard notify, advice.needsAttention else { return }

        // One notification per distinct problem, so rejoining the same broken
        // network does not turn into a stream of identical alerts.
        let fingerprint = advice.title + advice.detail
        guard fingerprint != lastNotified else { return }
        lastNotified = fingerprint
        postNotification()
    }

    /// Opens in Safari specifically. Chrome's HTTPS-First and Firefox's
    /// HTTPS-Only rewrite the plain-HTTP redirect that many portals depend on,
    /// and HSTS-pinned hosts make it unrecoverable. Safari does not do this.
    func perform() {
        switch advice.action {
        case let .open(url): openInSafari(url)
        case let .openSettings(pane): NSWorkspace.shared.open(pane.url)
        case .none: break
        }
    }

    private func openInSafari(_ url: URL) {
        guard let safari = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
            NSWorkspace.shared.open(url); return
        }
        NSWorkspace.shared.open([url], withApplicationAt: safari,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    private func postNotification() {
        let content = UNMutableNotificationContent()
        content.title = advice.title
        content.body = advice.detail
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString,
                                  content: content, trigger: nil))
    }
}

struct MenuContent: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.advice.title).font(.headline)
            Text(model.advice.detail)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let title = model.advice.actionTitle {
                Button(title) { model.perform() }
                    .buttonStyle(.borderedProminent)
            }

            Divider()
            Button(model.checking ? "Checking..." : "Check again") {
                Task { await model.check(notify: false) }
            }
            .disabled(model.checking)
            Toggle("Open at login", isOn: $model.launchAtLogin)
            Button("Quit Lobby") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 320)
    }
}
