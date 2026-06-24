import ArgumentParser
import Foundation

// MARK: - Card Group

/// `aidash card <subcommand>` — manage cards within containers.
struct Card: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "card",
        abstract: "Create, update, and delete cards.",
        subcommands: [
            Put.self,
            Delete.self,
        ]
    )

    // MARK: - card put

    struct Put: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "put",
            abstract: "Create or update a card."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Parent container UUID.")
        var containerID: String

        @Option(name: .long, help: "Card UUID.")
        var id: String

        @Option(name: .long, help: "Card type (metric, insight, agentSummary, todoList, trending, digest, sectionHeader).")
        var type: String

        @Option(name: .long, help: "Card size (small, medium, wide, hero).")
        var size: String

        @Option(name: .long, help: "Visual style: neutral, success, warning, accent.")
        var style: String?

        @Option(name: .long, help: "JSON payload string or @file.json path.")
        var payload: String

        func run() async throws {
            throw NotImplementedError(task: "T054")
        }
    }

    // MARK: - card delete

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a card."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Card UUID to delete.")
        var id: String

        func run() async throws {
            throw NotImplementedError(task: "T054")
        }
    }
}
