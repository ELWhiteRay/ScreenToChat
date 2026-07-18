import AppKit

if CommandLine.arguments.contains("--self-test") {
    ChatGPTBridge.selfTest()
    print("Self-test passed")
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
