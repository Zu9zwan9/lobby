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
            // The glyph is the whole status report for someone who never opens
            // the panel, so it changes shape, not just colour.
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
        advice = await Inspector.check().advice
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Critically damped, response 0.4. Apple's default for a move that carried
    /// no momentum of its own: it settles without overshoot, which is what a
    /// status panel wants. Bounce belongs to gestures, and there are none here.
    private var settle: Animation { .spring(duration: 0.4, bounce: 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            detail
            if let title = model.advice.actionTitle { primaryAction(title) }
            footer
        }
        .padding(16)
        .frame(width: 308)
        .animation(reduceMotion ? nil : settle, value: model.advice)
        .animation(reduceMotion ? nil : settle, value: model.checking)
    }

    // Symbol and title share a row so the status maps onto the words it
    // describes rather than floating above them.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: model.advice.needsAttention
                  ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(model.advice.needsAttention ? .orange : .green)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)

            Text(model.advice.title)
                // Large text reads too loose at default tracking, so tighten it.
                .font(.system(.title3, weight: .semibold))
                .tracking(-0.2)
                .lineSpacing(-1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var detail: some View {
        Text(model.advice.detail)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func primaryAction(_ title: String) -> some View {
        Button(title) { model.perform() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .keyboardShortcut(.defaultAction)
    }

    // Secondary controls recede. Only one thing on this panel is the point, and
    // giving Quit the same weight as the fix would say otherwise.
    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.check(notify: false) }
            } label: {
                HStack(spacing: 5) {
                    if model.checking {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    }
                    Text(model.checking ? "Checking" : "Check again")
                }
            }
            .buttonStyle(.link)
            .disabled(model.checking)

            Spacer()

            Menu {
                Toggle("Open at login", isOn: $model.launchAtLogin)
                Divider()
                Button("Quit Lobby") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .accessibilityLabel("More options")
        }
        .font(.callout)
    }
}
