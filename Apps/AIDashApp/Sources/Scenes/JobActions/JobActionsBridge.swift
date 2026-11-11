#if os(macOS)
import Foundation
import Observation
import AIDashCore

struct JobActionsSourceSnapshot {
    let actions: [JobActionsAction]
    let diagnostics: [JobActionsDiagnostic]
}

@MainActor
@Observable
final class JobActionsReviewModel {
    enum Phase: Equatable {
        case ready, recording, recorded, stale, cancelled
        case failed(String)
    }

    let action: JobActionsAction
    let proposal: JobActionsPresentParams
    var phase: Phase = .ready
    var acknowledgement: UserEvent?

    init(action: JobActionsAction, proposal: JobActionsPresentParams) {
        self.action = action
        self.proposal = proposal
    }

    var canConfirm: Bool {
        switch phase {
        case .ready, .failed: return true
        case .recording, .recorded, .stale, .cancelled: return false
        }
    }
}

@MainActor
protocol JobActionsReviewPresenting: AnyObject {
    func present(
        _ review: JobActionsReviewModel,
        confirm: @escaping @MainActor () -> Void,
        cancel: @escaping @MainActor () -> Void
    ) throws
    func focus(requestID: String)
    func close(requestID: String)
}

/// App-owned staging. The sole write closure is reachable only from the native presenter's
/// confirmation callback; neither snapshot nor present invokes it.
@MainActor
final class JobActionsBridge {
    private struct Stage {
        let review: JobActionsReviewModel
        let expiresAt: Date
    }

    private let registeredJobIDs: Set<String>
    private let readSources: () -> JobActionsSourceSnapshot
    private let readReceipts: () throws -> [UserEvent]
    private let recordReceipt: (JobActionsAction, [JobActionsResponse]) throws -> UserEvent
    private let nativeAvailable: () -> Bool
    private let presenter: any JobActionsReviewPresenting
    private let now: () -> Date
    private var stages: [String: Stage] = [:]
    private static let lifetime: TimeInterval = 300
    private static let maximumStages = 16

    init(
        registeredJobIDs: Set<String>,
        readSources: @escaping () -> JobActionsSourceSnapshot,
        readReceipts: @escaping () throws -> [UserEvent],
        recordReceipt: @escaping (JobActionsAction, [JobActionsResponse]) throws -> UserEvent,
        nativeAvailable: @escaping () -> Bool,
        presenter: any JobActionsReviewPresenting,
        now: @escaping () -> Date = Date.init
    ) {
        self.registeredJobIDs = registeredJobIDs
        self.readSources = readSources
        self.readReceipts = readReceipts
        self.recordReceipt = recordReceipt
        self.nativeAvailable = nativeAvailable
        self.presenter = presenter
        self.now = now
    }

    /// Throws `job-actions.bridge-unavailable` if the complete bounded snapshot cannot be encoded.
    func snapshot() throws -> JobActionsSnapshot {
        expireStages()
        let sources = readSources()
        var diagnostics = sources.diagnostics
        let receipts: [UserEvent]
        let storeReady: Bool
        do {
            receipts = try readReceipts()
            storeReady = true
        } catch {
            receipts = []
            storeReady = false
            diagnostics.append(.init(code: "store-unavailable"))
        }
        let canPresent = nativeAvailable()
        if !canPresent { diagnostics.append(.init(code: "present-unavailable")) }
        let entries = try sources.actions.map { action in
            JobActionsSnapshot.Entry(
                action: action,
                revision: try JobActionsValidation.revision(for: action),
                acknowledgement: acknowledgement(in: receipts, for: action)
            )
        }
        let result = JobActionsSnapshot(
            capturedAt: now(), present: canPresent && storeReady, entries: entries, diagnostics: diagnostics
        )
        guard try makeXPCEncoder().encode(result).count <= 512 * 1024 else {
            throw JobActionsBridgeError.make("bridge-unavailable")
        }
        return result
    }

    /// Throws typed validation, stale/conflict, unavailable-source/store or native-UI errors.
    /// Success only means staged review, unless an actual existing receipt is returned.
    func present(_ params: JobActionsPresentParams) throws -> JobActionsPresentResult {
        try JobActionsValidation.validatePresent(params)
        expireStages()
        let key = params.requestID.lowercased()
        if let stage = stages[key], stage.review.proposal != params {
            throw JobActionsBridgeError.make("request-conflict")
        }
        let action = try currentAction(params)
        try JobActionsValidation.validateResponses(params.responses, for: action)
        let receipts = try availableReceipts()
        if let receipt = acknowledgement(in: receipts, for: action) {
            return JobActionsPresentResult(requestID: params.requestID, acknowledgement: receipt)
        }
        guard nativeAvailable() else { throw JobActionsBridgeError.make("native-ui-unavailable") }
        if let stage = stages[key] {
            guard stage.review.phase != .cancelled && stage.review.phase != .stale else {
                throw JobActionsBridgeError.make("stale-action")
            }
            presenter.focus(requestID: params.requestID)
            return JobActionsPresentResult(requestID: params.requestID)
        }
        guard stages.count < Self.maximumStages else { throw JobActionsBridgeError.make("bridge-unavailable") }
        let review = JobActionsReviewModel(action: action, proposal: params)
        stages[key] = Stage(review: review, expiresAt: now().addingTimeInterval(Self.lifetime))
        do {
            try presenter.present(review, confirm: { [weak self] in
                self?.confirmFromNativeWindow(key: key, review: review)
            }, cancel: { [weak self] in
                self?.cancelFromNativeWindow(key: key, review: review)
            })
        } catch {
            stages.removeValue(forKey: key)
            throw JobActionsBridgeError.make("native-ui-unavailable")
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.lifetime))
            self?.expireStages()
        }
        return JobActionsPresentResult(requestID: params.requestID)
    }

    private func confirmFromNativeWindow(key: String, review: JobActionsReviewModel) {
        expireStages()
        guard let stage = stages[key], stage.review === review, review.canConfirm else { return }
        review.phase = .recording
        do {
            let action = try currentAction(review.proposal)
            try JobActionsValidation.validateResponses(review.proposal.responses, for: action)
            if let receipt = acknowledgement(in: try availableReceipts(), for: action) {
                review.acknowledgement = receipt
            } else {
                // Synchronous MainActor save: revalidation, duplicate read and append cannot interleave.
                review.acknowledgement = try recordReceipt(action, review.proposal.responses)
            }
            review.phase = .recorded
        } catch let error as XPCError {
            if error.code == "job-actions.stale-action" || error.code == "job-actions.unknown-action" {
                review.phase = .stale
            } else {
                review.phase = .failed(error.code.hasPrefix("schema.") ? "invalid-response" : Self.reason(error))
            }
        } catch {
            review.phase = .failed("persistence-failed")
        }
    }

    private func cancelFromNativeWindow(key: String, review: JobActionsReviewModel) {
        guard stages[key]?.review === review, review.phase != .recorded && review.phase != .stale else { return }
        review.phase = .cancelled
    }

    private func expireStages() {
        let expired = stages.filter { $0.value.expiresAt <= now() }
        for (key, stage) in expired {
            stages.removeValue(forKey: key)
            if stage.review.phase != .recorded { stage.review.phase = .stale }
            presenter.close(requestID: stage.review.proposal.requestID)
        }
    }

    private func currentAction(_ params: JobActionsPresentParams) throws -> JobActionsAction {
        guard registeredJobIDs.contains(params.jobID) else { throw JobActionsBridgeError.make("unknown-action") }
        let sources = readSources()
        guard !sources.diagnostics.contains(where: { $0.jobID == nil || $0.jobID == params.jobID }) else {
            throw JobActionsBridgeError.make("bridge-unavailable")
        }
        guard let action = sources.actions.first(where: { $0.jobID == params.jobID && $0.id == params.actionID }) else {
            throw JobActionsBridgeError.make("unknown-action")
        }
        guard try JobActionsValidation.revision(for: action) == params.revision else {
            throw JobActionsBridgeError.make("stale-action")
        }
        return action
    }

    private func availableReceipts() throws -> [UserEvent] {
        do { return try readReceipts() } catch { throw JobActionsBridgeError.make("bridge-unavailable") }
    }

    private func acknowledgement(in events: [UserEvent], for action: JobActionsAction) -> UserEvent? {
        JobActionsValidation.acknowledgement(in: events, for: action, registeredJobIDs: registeredJobIDs)
    }

    private static func reason(_ error: XPCError) -> String {
        let reason = String(error.code.split(separator: ".").last ?? "")
        return ["bridge-unavailable", "persistence-failed"].contains(reason) ? reason : "persistence-failed"
    }
}

enum JobActionsBridgeError {
    static func make(_ reason: String) -> XPCError {
        XPCError(code: "job-actions.\(reason)", message: message(reason))
    }

    static func message(_ reason: String) -> String {
        let fallback: String
        switch reason {
        case "invalid-request": fallback = "The action request is invalid. Refresh and try again."
        case "unknown-action": fallback = "This action is no longer available. Refresh Action Items."
        case "stale-action": fallback = "This action changed or the review expired. Refresh and review it again."
        case "invalid-response": fallback = "The proposed responses do not match this action."
        case "request-conflict": fallback = "This request ID belongs to a different proposal."
        case "native-ui-unavailable": fallback = "AIDash cannot open native review right now."
        case "persistence-failed": fallback = "The receipt could not be saved. Your proposed responses are retained. Try again."
        default: fallback = "AIDash cannot verify the current action or receipts. Refresh and try again."
        }
        return DashboardL10n.tr("job_actions.error.\(reason)", fallback)
    }
}
#endif
