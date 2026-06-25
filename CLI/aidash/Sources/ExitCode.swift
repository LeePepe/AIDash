import Foundation
import AIDashCore

/// Maps `XPCError.code` prefixes to CLI exit codes per `contracts/cli-surface.md` §"Exit codes".
///
/// | Code | Meaning                                                        |
/// |------|----------------------------------------------------------------|
/// | 0    | success                                                        |
/// | 1    | local validation failure (`schema.*`)                          |
/// | 2    | XPC transport failure (`xpc.*`)                                |
/// | 3    | remote error (everything else, e.g. `storage.*`, `not_found`)  |
public enum ExitCodeMapper {
    public static func code(for error: XPCError) -> Int32 {
        if error.code.hasPrefix("schema.") { return 1 }
        if error.code.hasPrefix("xpc.") { return 2 }
        return 3
    }
}
