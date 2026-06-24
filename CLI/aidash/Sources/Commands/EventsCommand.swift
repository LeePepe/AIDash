import ArgumentParser
import Foundation

// MARK: - Events Group

/// `aidash events <subcommand>` — read user events for agent consumption.
struct Events: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "Read user interaction events.",
        subcommands: [
            Pull.self,
        ]
    )

    // MARK: - events pull

    struct Pull: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "pull",
            abstract: "Pull user events since a given timestamp."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Lower bound (ISO-8601, YYYY-MM-DD, or 'yesterday').")
        var since: String

        @Option(name: .long, help: "Upper bound (ISO-8601, YYYY-MM-DD, or 'now').")
        var until: String?

        @Option(name: .long, help: "Filter by card UUID.")
        var cardID: String?

        @Option(name: .long, help: "Filter by action type (done, star).")
        var action: String?

        func run() async throws {
            throw NotImplementedError(task: "T055")
        }
    }
}
