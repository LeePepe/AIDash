import ArgumentParser
import Foundation

// MARK: - Briefing Group

/// `aidash briefing <subcommand>` — manage daily briefings.
struct Briefing: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "briefing",
        abstract: "Create, publish, and read briefings.",
        subcommands: [
            Put.self,
            Publish.self,
            Get.self,
        ]
    )

    // MARK: - briefing put

    struct Put: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "put",
            abstract: "Create or update a briefing's metadata."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Date (YYYY-MM-DD, 'today', or 'yesterday').")
        var date: String

        @Option(name: .long, help: "Human-readable agent identifier.")
        var generatedBy: String

        @Flag(name: .long, help: "Also publish the briefing immediately.")
        var published: Bool = false

        func run() async throws {
            throw NotImplementedError(task: "T050")
        }
    }

    // MARK: - briefing publish

    struct Publish: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "publish",
            abstract: "Mark a briefing as visible to readers."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Date (YYYY-MM-DD, 'today', or 'yesterday').")
        var date: String

        func run() async throws {
            throw NotImplementedError(task: "T051")
        }
    }

    // MARK: - briefing get

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Read a briefing."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Date (YYYY-MM-DD, 'today', 'yesterday', or 'latest').")
        var date: String

        func run() async throws {
            throw NotImplementedError(task: "T052")
        }
    }
}
