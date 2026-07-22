import AppKit
import Dispatch

// Manual entry point (no SwiftUI `App`/`MenuBarExtra` scene): AppKit owns the status item and a
// key-capable panel so the popover can be opened programmatically from a global hotkey.
//
// IMPORTANT: this file must NOT use a top-level `await`. A top-level `await` promotes the program
// to an *async* main, and calling the blocking `NSApplication.run()` from that async context
// leaves Swift's MainActor executor uncoordinated with the AppKit run loop — every
// `Task { @MainActor ... }` enqueued afterwards (start session, bootstrap, sync) is then starved
// and never runs. Keeping the GUI launch synchronous lets the run loop drain MainActor jobs. The
// self-test path runs its async work on a detached task and blocks on a semaphore instead.
@MainActor
func runLockin() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

if CommandLine.arguments.contains("--selftest") {
    // Run the async self-test on a detached task and drive the main dispatch queue with
    // `dispatchMain()`. Unlike a blocking semaphore wait, this keeps the main queue live so any
    // MainActor work inside the self-test is serviced instead of deadlocking. The task calls
    // `exit()` when finished, so `dispatchMain()` never needs to return.
    Task.detached {
        let ok = await SelfTest.run()
        exit(ok ? EXIT_SUCCESS : EXIT_FAILURE)
    }
    dispatchMain()
} else {
    // Top-level code runs on the main thread; assume MainActor isolation without awaiting so the
    // run loop starts synchronously and the concurrency runtime services MainActor Tasks.
    MainActor.assumeIsolated { runLockin() }
}
