import ArgumentParser

/// Global flags shared by all subcommands per `contracts/cli-surface.md`.
struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit machine-readable JSON on stdout.")
    var json: Bool = false

    @Flag(name: .long, help: "Suppress non-essential stdout.")
    var quiet: Bool = false
}
