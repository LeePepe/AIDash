import ArgumentParser

/// Top-level `aidash` CLI command.
///
/// Subcommands: briefing, container, card, events, schema.
/// Global flags (--json, --quiet) are inherited via `GlobalOptions`.
@main
struct AIDash: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aidash",
        abstract: "Agent-to-app bridge for AIDash briefings.",
        version: "1.0.0",
        subcommands: [
            Briefing.self,
            Container.self,
            Card.self,
            Events.self,
            Schema.self,
        ]
    )
}

// MARK: - Global Options

/// Flags shared by all subcommands per contracts/cli-surface.md.
struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of human format.")
    var json: Bool = false

    @Flag(name: .long, help: "Suppress non-essential stdout (errors still go to stderr).")
    var quiet: Bool = false
}
