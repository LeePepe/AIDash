#if os(macOS)
import Foundation
import Testing
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@MainActor
@Suite("Scheduled Pulse")
struct ScheduledPulseTests {
    @Test("registry contains exactly three live jobs and one reserved WorkIQ row")
    func registryShape() {
        #expect(ScheduledPulseRegistry.jobs.map(\.id) == [
            .aidataDigest, .prAutoReview, .myPRSupervisor, .workiqDigest
        ])
        #expect(ScheduledPulseRegistry.liveJobs.count == 3)
        #expect(ScheduledPulseRegistry.reservedJobs.map(\.id) == [.workiqDigest])
        #expect(ScheduledPulseRegistry.job(for: .workiqDigest)?.program == nil)
        #expect(ScheduledPulseRegistry.job(for: .workiqDigest)?.cadence == .reserved)
    }

    @Test("live job plist data has deterministic labels, programs, and cadence")
    func plistShape() throws {
        let digest = try #require(ScheduledPulseRegistry.job(for: .aidataDigest))
        let digestData = try #require(ScheduledPulseLaunchdInstaller.plistData(for: digest))
        let digestPlist = try #require(
            PropertyListSerialization.propertyList(from: digestData, options: [], format: nil) as? [String: Any]
        )
        #expect(digestPlist["Label"] as? String == "com.tianpli.aidash.job.aidata-digest")
        #expect(digestPlist["Program"] as? String == "aidata/scripts/aidata_digest_run.sh")
        let calendar = try #require(digestPlist["StartCalendarInterval"] as? [String: Any])
        #expect(calendar["Hour"] as? Int == 4)
        #expect(calendar["Minute"] as? Int == 0)
        #expect(calendar["TimeZone"] as? String == "Asia/Shanghai")

        let review = try #require(ScheduledPulseRegistry.job(for: .prAutoReview))
        let reviewData = try #require(ScheduledPulseLaunchdInstaller.plistData(for: review))
        let reviewPlist = try #require(
            PropertyListSerialization.propertyList(from: reviewData, options: [], format: nil) as? [String: Any]
        )
        #expect(reviewPlist["Label"] as? String == "com.tianpli.aidash.job.pr-auto-review")
        #expect(reviewPlist["Program"] as? String == "~/Development/handoff/pr-auto-review/precheck.py")
        #expect(reviewPlist["StartInterval"] as? Int == 300)
        let workiq = try #require(ScheduledPulseRegistry.job(for: .workiqDigest))
        #expect(ScheduledPulseLaunchdInstaller.plistData(for: workiq) == nil)
    }

    @Test("installer plan is idempotent and skips the reserved job")
    func installPlan() throws {
        let digest = try #require(ScheduledPulseRegistry.job(for: .aidataDigest))
        let plist = try #require(ScheduledPulseLaunchdInstaller.plistData(for: digest))
        #expect(ScheduledPulseLaunchdInstaller.plan(installed: plist, expected: plist, isLive: true) == .upToDate)
        #expect(ScheduledPulseLaunchdInstaller.plan(installed: nil, expected: plist, isLive: true) == .install)
        #expect(ScheduledPulseLaunchdInstaller.plan(installed: Data("stale".utf8), expected: plist, isLive: true) == .install)
        #expect(ScheduledPulseLaunchdInstaller.plan(installed: nil, expected: nil, isLive: false) == .skipReserved)
    }

    @Test("installer writes only live plists and bootstraps the user GUI domain")
    func installerEffects() {
        var writes: [(URL, Data)] = []
        var launchctlCalls: [[String]] = []
        let installer = ScheduledPulseLaunchdInstaller(
            plistURL: { _ in URL(fileURLWithPath: "/dev/null") },
            installedPlist: { _ in nil },
            createDirectory: { _ in },
            writePlist: { url, data in writes.append((url, data)) },
            launchctl: { args in
                launchctlCalls.append(args)
                return .init(arguments: args, terminationStatus: 0, stdout: "", stderr: "", launchError: nil)
            }
        )

        let outcomes = installer.registerLiveJobs()
        #expect(outcomes == Array(repeating: .registered, count: 3))
        #expect(writes.count == 3)
        #expect(launchctlCalls.count == 3)
        #expect(launchctlCalls.allSatisfy { $0.count == 3 && $0[0] == "bootstrap" })
        #expect(launchctlCalls.allSatisfy { $0.count == 3 && $0[1] == "gui/\(getuid())" })
        #expect(launchctlCalls.allSatisfy { $0.count == 3 && $0[2] == "/dev/null" })
        #expect(!launchctlCalls.contains { $0.contains("workiq-digest") })
    }

    @Test("filters retain the reserved WorkIQ row and order exceptions critical then warning")
    func filteringAndExceptions() {
        let jobs = ScheduledPulseRegistry.jobs
        let statuses = jobs.map { definition -> ScheduledJobStatus in
            switch definition.id {
            case .aidataDigest:
                return ScheduledJobStatus(definition: definition, health: .warning)
            case .prAutoReview:
                return ScheduledJobStatus(definition: definition, health: .critical)
            case .myPRSupervisor:
                return ScheduledJobStatus(definition: definition, health: .expectedOnButIdle)
            case .workiqDigest:
                return ScheduledJobStatus(definition: definition, health: .reserved)
            }
        }
        let snapshot = ScheduledPulseSnapshot(capturedAt: Date(timeIntervalSince1970: 0), jobs: statuses)
        #expect(ScheduledPulseLogic.defaultHealthFilter(for: snapshot) == .unhealthy)
        #expect(ScheduledPulseLogic.filteredJobs(from: snapshot, scheduler: .all, health: .unhealthy).last?.id == .workiqDigest)
        #expect(ScheduledPulseLogic.exceptions(from: snapshot).map(\.id) == [.prAutoReview, .aidataDigest, .myPRSupervisor])
    }

    @Test("menubar pulse routing is read-only and opens Scheduled Pulse")
    func menubarRouting() {
        var openCount = 0
        let snapshot = ScheduledPulseSnapshot(
            capturedAt: Date(timeIntervalSince1970: 0),
            jobs: ScheduledPulseRegistry.jobs.map { definition in
                ScheduledJobStatus(definition: definition, health: definition.isLive ? .critical : .reserved)
            }
        )
        let view = MenuBarStatusView(
            state: .loading,
            onOpenScheduledPulse: { openCount += 1 },
            scheduledPulseSnapshot: snapshot
        )
        view.onOpenScheduledPulse()
        #expect(openCount == 1)
        #expect(ScheduledPulseLogic.exceptions(from: snapshot).count == 3)
    }
}
#endif
