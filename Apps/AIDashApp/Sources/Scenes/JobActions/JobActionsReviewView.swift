#if os(macOS)
import AppKit
import SwiftUI
import DesignKit
import AIDashCore

/// Read-only review of the authoritative action and the staged proposal, outside Briefing.
@MainActor
struct JobActionsReviewView: View {
    @Environment(\.theme) private var theme
    let review: JobActionsReviewModel
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            VStack(alignment: .leading, spacing: Space.gap) {
                Text("job_actions.review.title").font(.title2.weight(.semibold))
                Text("job_actions.review.source").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.cardPadding)
            .padding(.top, Space.cardPadding)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.cardPadding) {
                    VStack(alignment: .leading, spacing: Space.gap) {
                        HStack(spacing: 6) {
                            Text(verbatim: jobLabel).font(.caption).foregroundStyle(.secondary)
                            if let priority = review.action.priority, !priority.isEmpty {
                                StatusPill(priority, tone: priorityTone(priority))
                            }
                            if let status = review.action.status, !status.isEmpty {
                                StatusPill(status, tone: statusTone(status))
                            }
                            if let source = review.action.source, !source.isEmpty {
                                Text(verbatim: source)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            if let ref = review.action.ref, !ref.isEmpty {
                                Text(verbatim: ref)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(verbatim: review.action.title).font(.headline)
                        Text(verbatim: review.action.description)
                            .font(.body)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = URLPolicy.validate(review.action.url) {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label(
                                    DashboardL10n.tr("dashboard.actions.open_link", "Open Link"),
                                    systemImage: "arrow.up.right.square"
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .frame(minHeight: 28)
                        }
                    }
                    ForEach(review.action.controls) { control in
                        VStack(alignment: .leading, spacing: Space.gap) {
                            Text(verbatim: control.title).font(.headline)
                            let value = review.proposal.responses.first { $0.controlID == control.id }?.value ?? ""
                            if value.isEmpty {
                                Text("job_actions.review.empty_value").foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: value).textSelection(.enabled)
                            }
                        }
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.cardPadding)
                        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: Radius.card))
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.cardPadding)
            }
            Divider()
            VStack(alignment: .leading, spacing: Space.gap) {
                status
                Text("job_actions.review.notice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(action: cancel) {
                        Text(review.phase == .recorded
                             ? LocalizedStringKey("job_actions.review.close")
                             : LocalizedStringKey("job_actions.review.cancel"))
                            .frame(minHeight: 28)
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(review.phase == .recording)
                    Button(action: confirm) {
                        Text("job_actions.review.confirm").frame(minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!review.canConfirm)
                }
            }
            .padding(.horizontal, Space.cardPadding)
            .padding(.bottom, Space.cardPadding)
        }
        .lineLimit(nil)
        .background(theme.neutrals.bg)
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 640, minHeight: 360, idealHeight: 600, maxHeight: 720)
    }

    @ViewBuilder private var status: some View {
        switch review.phase {
        case .ready:
            Text("job_actions.review.pending").font(.caption).foregroundStyle(.secondary)
        case .recording:
            HStack {
                ProgressView().controlSize(.small)
                Text("job_actions.review.recording").font(.body)
            }
        case .recorded:
            Label {
                Text("job_actions.review.recorded")
            } icon: {
                Image(systemName: "checkmark.circle").accessibilityHidden(true)
            }
            .foregroundStyle(theme.successOnSubtle)
        case .stale:
            Text(JobActionsBridgeError.message("stale-action"))
                .font(.body).foregroundStyle(theme.warningOnSubtle)
        case .failed(let reason):
            Text(JobActionsBridgeError.message(reason))
                .font(.body).foregroundStyle(theme.dangerOnSubtle)
        case .cancelled:
            Text("job_actions.review.cancelled").font(.body).foregroundStyle(.secondary)
        }
    }

    private func priorityTone(_ priority: String) -> PillTone {
        switch DashboardActionPriority.from(rawPriority: priority) {
        case .p0: return .danger
        case .p1: return .warning
        case .p2: return .neutral
        }
    }

    private func statusTone(_ status: String) -> PillTone {
        switch DashboardActionStatus.from(rawStatus: status) {
        case .blocked: return .danger
        case .triage: return .warning
        case .inProgress: return .primary
        case .done: return .success
        }
    }

    private var jobLabel: String {
        ScheduledPulseRegistry.jobs.first { $0.id.rawValue == review.action.jobID }?.displayName
            ?? review.action.jobID
    }
}

@MainActor
final class JobActionsNativePresenter: JobActionsReviewPresenting {
    private var windows: [String: JobActionsReviewWindow] = [:]

    /// Throws `job-actions.native-ui-unavailable` outside a real AppKit app.
    func present(
        _ review: JobActionsReviewModel,
        confirm: @escaping @MainActor () -> Void,
        cancel: @escaping @MainActor () -> Void
    ) throws {
        guard JobActionsSources.isProductionEnvironment, let app = NSApp else {
            throw JobActionsBridgeError.make("native-ui-unavailable")
        }
        let requestID = review.proposal.requestID
        let view = JobActionsReviewView(review: review, confirm: confirm, cancel: { [weak self] in
            self?.close(requestID: requestID)
        })
        .designTheme(seed: .lime, neutral: .slate)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = String(localized: "job_actions.review.title")
        window.contentView = NSHostingView(rootView: view)
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.contentMaxSize = NSSize(width: 640, height: 720)
        window.isReleasedWhenClosed = false
        let controller = JobActionsReviewWindow(window: window) { [weak self] in
            cancel()
            self?.windows.removeValue(forKey: requestID.lowercased())
        }
        windows[requestID.lowercased()] = controller
        window.center()
        app.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func focus(requestID: String) {
        NSApp?.activate(ignoringOtherApps: true)
        windows[requestID.lowercased()]?.window?.makeKeyAndOrderFront(nil)
    }

    func close(requestID: String) {
        windows[requestID.lowercased()]?.close()
    }
}

@MainActor
private final class JobActionsReviewWindow: NSWindowController, NSWindowDelegate {
    private let didClose: () -> Void

    init(window: NSWindow, didClose: @escaping () -> Void) {
        self.didClose = didClose
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { return nil }

    func windowWillClose(_ notification: Notification) {
        didClose()
    }
}
#endif
