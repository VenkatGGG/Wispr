@preconcurrency import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if running.count > 1 {
            NSLog("Another instance of Flow is already running — exiting.")
            NSApp.terminate(nil)
            return
        }

        do {
            let controller = try AppController()
            appController = controller
            controller.start()
        } catch {
            NSLog("Failed to start Flow: \(error.localizedDescription)")
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appController?.stop()
    }
}
