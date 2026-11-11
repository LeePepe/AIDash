#if os(macOS)
import Foundation
import SwiftData
import AppKit
import AIDashCore

/// Reads only registered actions.jsonl files. No telemetry, launchctl, precheck or source mutations.
@MainActor
enum JobActionsSources {
    static let maximumFileBytes = 256 * 1024
    typealias ReadFile = (URL, Int) throws -> Data

    static func load(home: URL, jobs: [ScheduledJobDefinition], read: ReadFile) -> JobActionsSourceSnapshot {
        let root = home.appendingPathComponent("Library/Application Support/AIDash/jobs", isDirectory: true)
        var actions: [JobActionsAction] = []
        var diagnostics: [JobActionsDiagnostic] = []
        for job in jobs {
            do {
                let url = root.appendingPathComponent(job.id.rawValue).appendingPathComponent("actions.jsonl")
                let data = try read(url, maximumFileBytes + 1)
                guard data.count <= maximumFileBytes else {
                    diagnostics.append(.init(code: "source-oversized", jobID: job.id.rawValue))
                    continue
                }
                actions += try decode(data, jobID: job.id.rawValue)
            } catch {
                let code: String
                let cocoa = error as NSError
                if cocoa.domain == NSCocoaErrorDomain,
                   [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(cocoa.code) {
                    code = "source-missing"
                } else if error is DecodingError || error is XPCError {
                    code = "source-malformed"
                } else {
                    code = "source-unavailable"
                }
                diagnostics.append(.init(code: code, jobID: job.id.rawValue))
            }
        }
        return JobActionsSourceSnapshot(actions: actions, diagnostics: diagnostics)
    }

    /// Throws a safe validation error for invalid UTF-8, duplicate IDs, wrong jobs or invalid declarations.
    static func decode(_ data: Data, jobID: String) throws -> [JobActionsAction] {
        guard let text = String(data: data, encoding: .utf8) else { throw invalidSource() }
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count <= 128 else { throw invalidSource() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid action date")
            }
            return date
        }
        let actions = try lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { line in
            let action = try decoder.decode(JobActionsAction.self, from: Data(line.utf8))
            guard action.jobID == jobID else { throw invalidSource() }
            try JobActionsValidation.validateAction(action)
            return action
        }
        guard Set(actions.map(\.id)).count == actions.count else { throw invalidSource() }
        return actions
    }

    static func production() -> JobActionsSourceSnapshot {
        guard isProductionEnvironment else {
            return JobActionsSourceSnapshot(actions: [], diagnostics: [.init(code: "bridge-unavailable")])
        }
        return load(
            home: LiveMenuBarSystemStatusProvider.realUserHomeDirectoryURL(),
            jobs: ScheduledPulseRegistry.jobs
        ) { url, limit in
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return try handle.read(upToCount: limit) ?? Data()
        }
    }

    static var isProductionEnvironment: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] == nil && env["XCTestBundlePath"] == nil
    }

    private static func invalidSource() -> XPCError {
        XPCError(code: "job-actions.source-malformed", message: "Invalid registered action source.")
    }
}

@MainActor
enum JobActionsReceiptStore {
    /// Throws on an unavailable/oversized store read; never converts failed reads into no receipts.
    static func read(container: ModelContainer, jobs: Set<String>) throws -> [UserEvent] {
        let context = ModelContext(container)
        return try jobs.sorted().flatMap { jobID in
            try read(context: context, jobID: jobID)
        }
    }

    static func read(context: ModelContext, jobID: String) throws -> [UserEvent] {
        let cardID = "scheduled-pulse/\(jobID)"
        let actionRaw = UserEventAction.acknowledgeJobAction.rawValue
        let cardType = "scheduledPulse"
        var descriptor = FetchDescriptor<UserEventModel>(predicate: #Predicate {
            $0.cardId == cardID && $0.actionRaw == actionRaw && $0.cardType == cardType
        })
        descriptor.fetchLimit = 4097
        let models = try context.fetch(descriptor)
        guard models.count <= 4096,
              models.allSatisfy({ ($0.itemRef?.utf8.count ?? 0) <= JobActionsValidation.maximumRequestBytes }) else {
            throw JobActionsBridgeError.make("bridge-unavailable")
        }
        return models.map { model in
            UserEvent(id: model.id, timestamp: model.timestamp, device: model.device, cardId: model.cardId,
                      action: .acknowledgeJobAction, itemRef: model.itemRef, cardType: model.cardType)
        }
    }
}

@MainActor
extension JobActionsBridge {
    static func production(container: @escaping () -> ModelContainer?) -> JobActionsBridge {
        let jobs = Set(ScheduledPulseRegistry.jobs.map { $0.id.rawValue })
        return JobActionsBridge(
            registeredJobIDs: jobs,
            readSources: JobActionsSources.production,
            readReceipts: {
                guard JobActionsSources.isProductionEnvironment, let store = container() else {
                    throw JobActionsBridgeError.make("bridge-unavailable")
                }
                return try JobActionsReceiptStore.read(container: store, jobs: jobs)
            },
            recordReceipt: { action, responses in
                guard JobActionsSources.isProductionEnvironment, let store = container() else {
                    throw JobActionsBridgeError.make("persistence-failed")
                }
                return try UserEventWriter(container: store).recordReviewedJobAction(action: action, responses: responses)
            },
            nativeAvailable: { JobActionsSources.isProductionEnvironment && NSApp != nil },
            presenter: JobActionsNativePresenter()
        )
    }
}
#endif
