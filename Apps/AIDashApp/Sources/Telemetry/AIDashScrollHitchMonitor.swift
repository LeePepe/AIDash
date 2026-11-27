import Foundation

struct AIDashScrollHitchSessionSummary: Equatable, Sendable {
    let section: String
    let hitchCount: Int
    let severeHitchCount: Int
    let maxFrameMilliseconds: Int64
    let durationMilliseconds: Int64
}

@MainActor
final class AIDashScrollHitchMonitor {
    static let defaultHitchThresholdMilliseconds: Int64 = 33
    static let defaultSevereHitchThresholdMilliseconds: Int64 = 100

    private let hitchThresholdMilliseconds: Int64
    private let severeHitchThresholdMilliseconds: Int64
    private let monotonicNow: () -> Duration
    private let onSessionCompleted: (AIDashScrollHitchSessionSummary) -> Void

    private var activeSection: String?
    private var sessionStart: Duration?
    private var lastFrameTimestamp: Duration?
    private var hitchCount = 0
    private var severeHitchCount = 0
    private var maxFrameMilliseconds: Int64 = 0
    private var samplingTask: Task<Void, Never>?

    init(
        hitchThresholdMilliseconds: Int64 = AIDashScrollHitchMonitor.defaultHitchThresholdMilliseconds,
        severeHitchThresholdMilliseconds: Int64 = AIDashScrollHitchMonitor.defaultSevereHitchThresholdMilliseconds,
        monotonicNow: @escaping () -> Duration = { ContinuousClock.now.duration(to: ContinuousClock.now) },
        onSessionCompleted: @escaping (AIDashScrollHitchSessionSummary) -> Void
    ) {
        self.hitchThresholdMilliseconds = hitchThresholdMilliseconds
        self.severeHitchThresholdMilliseconds = severeHitchThresholdMilliseconds
        self.monotonicNow = monotonicNow
        self.onSessionCompleted = onSessionCompleted
    }

    static func live(
        onSessionCompleted: @escaping (AIDashScrollHitchSessionSummary) -> Void
    ) -> AIDashScrollHitchMonitor {
        let origin = ContinuousClock.now
        return AIDashScrollHitchMonitor(
            monotonicNow: { origin.duration(to: ContinuousClock.now) },
            onSessionCompleted: onSessionCompleted
        )
    }

    var isScrolling: Bool {
        activeSection != nil
    }

    func beginScroll(section: String, startSamplingLoop: Bool = true) {
        if let activeSection, activeSection != section {
            endScroll()
        }
        guard activeSection == nil else { return }
        let now = monotonicNow()
        activeSection = section
        sessionStart = now
        lastFrameTimestamp = now
        hitchCount = 0
        severeHitchCount = 0
        maxFrameMilliseconds = 0
        guard startSamplingLoop else { return }
        samplingTask?.cancel()
        samplingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, let self, self.isScrolling else { break }
                self.sampleFrame()
            }
        }
    }

    func sampleFrame() {
        guard isScrolling else { return }
        let now = monotonicNow()
        guard let previous = lastFrameTimestamp else {
            lastFrameTimestamp = now
            return
        }
        lastFrameTimestamp = now
        recordFrameDelta(now - previous)
    }

    func recordFrameDeltaMilliseconds(_ frameMilliseconds: Int64) {
        guard isScrolling, frameMilliseconds >= 0 else { return }
        if frameMilliseconds > maxFrameMilliseconds {
            maxFrameMilliseconds = frameMilliseconds
        }
        if frameMilliseconds > hitchThresholdMilliseconds {
            hitchCount += 1
        }
        if frameMilliseconds > severeHitchThresholdMilliseconds {
            severeHitchCount += 1
        }
    }

    @discardableResult
    func endScroll() -> AIDashScrollHitchSessionSummary? {
        samplingTask?.cancel()
        samplingTask = nil
        guard let section = activeSection, let start = sessionStart else {
            resetSessionState()
            return nil
        }
        sampleFrame()
        let durationMs = max(0, Self.completeMilliseconds(monotonicNow() - start) ?? 0)
        let summary = AIDashScrollHitchSessionSummary(
            section: section,
            hitchCount: hitchCount,
            severeHitchCount: severeHitchCount,
            maxFrameMilliseconds: maxFrameMilliseconds,
            durationMilliseconds: durationMs
        )
        resetSessionState()
        if summary.hitchCount > 0 {
            onSessionCompleted(summary)
        }
        return summary
    }

    private func recordFrameDelta(_ delta: Duration) {
        guard let milliseconds = Self.completeMilliseconds(delta) else { return }
        recordFrameDeltaMilliseconds(milliseconds)
    }

    private func resetSessionState() {
        activeSection = nil
        sessionStart = nil
        lastFrameTimestamp = nil
        hitchCount = 0
        severeHitchCount = 0
        maxFrameMilliseconds = 0
    }

    private static func completeMilliseconds(_ duration: Duration) -> Int64? {
        let components = duration.components
        guard components.seconds >= 0, components.attoseconds >= 0 else { return nil }
        let seconds = components.seconds.multipliedReportingOverflow(by: 1_000)
        guard !seconds.overflow else { return nil }
        let milliseconds = Int64(components.attoseconds / 1_000_000_000_000_000)
        let total = seconds.partialValue.addingReportingOverflow(milliseconds)
        return total.overflow ? nil : total.partialValue
    }
}
