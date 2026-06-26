# ADR-001: Use of `nonisolated(unsafe)` for XPC Reply Closure

## Status

Accepted

## Context

The `AIDashXPCServiceProtocol` defines `execute(requestData:reply:)` as an
`@objc` protocol method. This method:

1. Must be `nonisolated` because `NSXPCConnection` calls it from an arbitrary
   XPC dispatch queue — not the main actor.
2. Receives a `reply` closure of type `@escaping (Data) -> Void` that must be
   called exactly once to send the response back to the CLI client.

The handler logic lives on `@MainActor` (required by SwiftData's
`ModelContext`). We bridge the gap by spawning a `Task { @MainActor in ... }`
from the `nonisolated` method. However, Swift 6 strict concurrency flags the
capture of `reply` inside the `@MainActor` task as a "sending" violation —
the closure is not `Sendable`, so passing it across isolation boundaries is
statically rejected.

## Decision

Use `nonisolated(unsafe) let reply = reply` to rebind the closure as a local
that suppresses the sending diagnostic:

```swift
nonisolated func execute(requestData: Data, reply: @escaping (Data) -> Void) {
    nonisolated(unsafe) let reply = reply
    Task { @MainActor in
        let response = await self.handleRequest(requestData)
        let encoded = (try? JSONEncoder.xpc.encode(response)) ?? Data()
        reply(encoded)
    }
}
```

## Safety argument

- `reply` is called exactly once, on a single path, after all async work
  completes. There is no concurrent access.
- The XPC runtime guarantees the connection (and therefore the closure) stays
  alive until `reply` is invoked.
- No mutable shared state is accessed through the closure — it is purely a
  callback that writes bytes to the XPC channel.
- This pattern is the idiomatic workaround recommended by the Swift
  concurrency team for `@objc` protocol methods that bridge sync callbacks
  into structured concurrency.

## Alternatives considered

1. **`@unchecked Sendable` wrapper struct** — more boilerplate, same safety
   argument, harder to read.
2. **`withCheckedContinuation`** — doesn't help because the protocol
   signature is fixed as a callback, not async/await.
3. **Making the entire class `nonisolated`** — breaks SwiftData usage which
   requires `@MainActor`.

## Consequences

- The `nonisolated(unsafe)` annotation is limited to a single 6-line method
  in `XPCHandlers.swift`. If Apple provides a `Sendable`-compatible XPC
  callback mechanism in a future SDK, this annotation can be removed.
