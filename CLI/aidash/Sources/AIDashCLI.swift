import ArgumentParser
import AIDashCore
import Foundation

@main
struct AIDash: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aidash",
        abstract: "AIDash CLI — publish briefings, query schema, pull events.",
        version: "1.0.0",
        subcommands: [
            BriefingCommand.self,
            ContainerCommand.self,
            CardCommand.self,
            EventsCommand.self,
            SchemaCommand.self,
        ]
    )

    // MARK: - Root-level global flags
    //
    // Declared on the root command so `parseAsRoot()` accepts
    // `aidash --json briefing publish ...` and `aidash --quiet ...`.
    // Leaf commands also expose them via `GlobalOptions` (via OptionGroup)
    // so the same flags work after the subcommand verb. `GlobalOptions`
    // additionally inspects `ProcessInfo.processInfo.arguments` so that the
    // effective flags can be observed from any leaf regardless of position.

    @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of human format.")
    var json: Bool = false

    @Flag(name: .long, help: "Suppress non-essential stdout (errors still go to stderr).")
    var quiet: Bool = false

    // MARK: - Global error handler (T044)

    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCmd = command as? any AsyncParsableCommand {
                try await asyncCmd.run()
            } else {
                try command.run()
            }
        } catch let xpcError as XPCError {
            // XPC-layer or domain errors → emit JSON envelope and exit with mapped code
            try? JSONOutput().emit(error: xpcError, requestId: nil)
            Darwin.exit(ExitCodeMapper.code(for: xpcError))
        } catch {
            // ArgumentParser routes `--help` / `--version` here as "errors" with
            // exit code `.success`; those must print to stdout (or stderr per
            // ArgumentParser) and exit 0 — they are NOT contract errors. For
            // everything else (parser errors, validation failures, unknown
            // errors), the CLI contract requires a JSON envelope on stderr with
            // a mapped exit code.
            let argParserExit = Self.exitCode(for: error)
            if argParserExit == ExitCode.success {
                // Let ArgumentParser handle help/version output and exit 0.
                Self.exit(withError: error)
            }
            let wrapped = XPCError(
                code: "schema.invalid_argument",
                message: Self.fullMessage(for: error),
                field: nil,
                got: nil,
                allowed: nil
            )
            try? JSONOutput().emit(error: wrapped, requestId: nil)
            Darwin.exit(ExitCodeMapper.code(for: wrapped))
        }
    }
}

// MARK: - Briefing

struct BriefingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "briefing",
        abstract: "Manage daily briefings.",
        subcommands: [
            BriefingPutCommand.self,
            BriefingPublishCommand.self,
            BriefingGetCommand.self,
        ]
    )
}

// `BriefingPutCommand` is defined in `Commands/BriefingPutCommand.swift` (T050).

// `BriefingGetCommand` is defined in `Commands/BriefingGetCommand.swift` (T052).

// MARK: - Container

struct ContainerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "container",
        abstract: "Manage briefing containers.",
        subcommands: [
            ContainerPutCommand.self,
            ContainerDeleteCommand.self,
        ]
    )
}

// ContainerPutCommand: real implementation in Commands/ContainerPutCommand.swift
// ContainerDeleteCommand: real implementation in Commands/ContainerDeleteCommand.swift (T175)

// MARK: - Card

struct CardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "card",
        abstract: "Manage cards within containers.",
        subcommands: [
            CardPutCommand.self,
            CardDeleteCommand.self,
        ]
    )
}

// `CardPutCommand` is defined in `Commands/CardPutCommand.swift` (T054).
// `CardDeleteCommand` is defined in `Commands/CardDeleteCommand.swift` (T176).

// MARK: - Events

struct EventsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "Query user interaction events.",
        subcommands: [
            EventsPullCommand.self,
        ]
    )
}

// `EventsPullCommand` is defined in `Commands/EventsPullCommand.swift`
// (spec 002 T002 — the read half of the star feedback loop).

// MARK: - Schema

struct SchemaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Query the AIDash schema.",
        subcommands: [
            SchemaListCommand.self,
        ]
    )
}

// `SchemaListCommand` is defined in `Commands/SchemaListCommand.swift` (T055).
