/// Error thrown by stub command bodies to signal not-yet-implemented behavior.
/// ArgumentParser prints the description to stderr and exits with code 1.
struct NotImplementedError: Error, CustomStringConvertible {
    let task: String

    var description: String {
        "Error: command not yet implemented (see \(task))"
    }
}
