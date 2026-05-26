import AppKit
import CoreGraphics

enum ScreenRecordingPermission {
    static func authorize(_ completion: @escaping (Bool) -> Void) {
        if CGPreflightScreenCaptureAccess() {
            completion(true)
            return
        }

        // Force activation so the TCC prompt comes to the foreground on a
        // menu-bar (LSUIElement) app. CGRequestScreenCaptureAccess triggers the
        // prompt the first time; subsequent denies are sticky.
        NSApp.activate(ignoringOtherApps: true)
        let granted = CGRequestScreenCaptureAccess()
        GhostLog.write("Screen recording permission \(granted ? "GRANTED" : "DENIED / not yet decided")")

        if granted {
            completion(true)
        } else {
            showSettingsAlert()
            completion(false)
        }
    }

    private static func showSettingsAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Access Needed"
        alert.informativeText = """
        GhostMind needs Screen Recording access to hear audio from your speaker (Zoom, Meet, browser tabs).

        Open System Settings → Privacy & Security → Screen Recording, then enable GhostMind and relaunch the app.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }
}
