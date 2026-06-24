import ArgumentParser
import Foundation

// MARK: - Schema Group

/// `aidash schema <subcommand>` — introspect the CLI schema.
struct Schema: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Introspect card types and payload schemas.",
        subcommands: [
            List.self,
        ]
    )

    // MARK: - schema list

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Print the full schema as JSON."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Filter output to a single card type.")
        var type: String?

        func run() async throws {
            throw NotImplementedError(task: "T055")
        }
    }
}
