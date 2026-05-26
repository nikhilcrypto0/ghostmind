import AppKit
import AVFoundation

enum MicPermission {
    static func authorize(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)

        case .notDetermined:
            // Menu-bar (LSUIElement) apps can have TCC prompts appear behind
            // other windows. Forcing activation surfaces the prompt reliably.
            NSApp.activate(ignoringOtherApps: true)
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    GhostLog.write("Microphone permission \(granted ? "GRANTED" : "DENIED") by user prompt")
                    if !granted { showSettingsAlert() }
                    completion(granted)
                }
            }

        case .denied, .restricted:
            GhostLog.write("Microphone permission previously denied — opening Settings")
            showSettingsAlert()
            completion(false)

        @unknown default:
            completion(false)
        }
    }

    private static func showSettingsAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Access Needed"
        alert.informativeText = """
        GhostMind needs microphone access to transcribe your voice.

        Open System Settings → Privacy & Security → Microphone, then enable GhostMind.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            NSWorkspace.shared.open(url)
        }
    }
}
