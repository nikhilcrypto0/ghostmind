import AppKit
import SwiftUI
import AVFoundation
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindowController: OverlayWindowController?
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private var setupWindowController: SetupWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        setupOverlay()
        HotkeyManager.shared.register()
        checkFirstRunSetup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AudioCaptureManager.shared.stop()
        SystemAudioCapture.shared.stop()
    }

    // MARK: - First-run setup

    private func checkFirstRunSetup() {
        let hasAnthropicKey = keyFileHasContent("/.ghostmind_api_key")
        let hasDeepgramKey  = keyFileHasContent("/.deepgram_api_key")

        if hasAnthropicKey && hasDeepgramKey {
            startAudio()
        } else {
            setupWindowController = SetupWindowController(onComplete: { [weak self] in
                self?.startAudio()
                self?.setupWindowController = nil
            })
            setupWindowController?.show()
        }
    }

    private func keyFileHasContent(_ relativePath: String) -> Bool {
        let path = NSHomeDirectory() + relativePath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Audio

    private func startAudio() {
        GhostLog.write("Starting transcription engine")
        NotificationCenter.default.post(name: .whisperLoading, object: nil)
        TranscriptionManager.shared.setup()

        NotificationCenter.default.addObserver(forName: .whisperReady, object: nil, queue: .main) { n in
            guard n.userInfo?["error"] == nil else { return }
            guard ContextManager.shared.captureSystemAudio else { return }
            GhostLog.write("Auto-starting system audio capture for interviewer voice")
            SystemAudioCapture.shared.start()
        }
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "GhostMind")

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Show / Hide  ⌘⇧Space", action: #selector(toggleOverlay), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let contextItem = NSMenuItem(title: "Interview Context...", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(contextItem)

        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        launchAtLoginItem = loginItem
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear Response  ⌘⇧X", action: #selector(clearResponse), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit GhostMind", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                launchAtLoginItem?.state = .off
            } else {
                try SMAppService.mainApp.register()
                launchAtLoginItem?.state = .on
            }
        } catch {
            GhostLog.write("Launch at login toggle failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Overlay setup

    private func setupOverlay() {
        overlayWindowController = OverlayWindowController()
        overlayWindowController?.showWindow(nil)
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleToggleOverlay),  name: .toggleOverlay,  object: nil)
        nc.addObserver(self, selector: #selector(handleClearResponse),  name: .clearResponse,  object: nil)
        nc.addObserver(self, selector: #selector(handleToggleMic),      name: .toggleMic,      object: nil)
    }

    func toggle() { overlayWindowController?.toggle() }
    func clear()  { overlayWindowController?.clear() }

    @objc private func toggleOverlay()       { overlayWindowController?.toggle() }
    @objc private func clearResponse()       { overlayWindowController?.clear() }
    @objc private func handleToggleOverlay() { overlayWindowController?.toggle() }
    @objc private func handleClearResponse() { overlayWindowController?.clear() }

    @objc private func handleToggleMic() {
        if AudioCaptureManager.shared.isRunning {
            AudioCaptureManager.shared.stop()
            NotificationCenter.default.post(name: .micMuted, object: nil)
        } else {
            AudioCaptureManager.shared.start()
            NotificationCenter.default.post(name: .micUnmuted, object: nil)
        }
    }

}

extension Notification.Name {
    static let toggleOverlay  = Notification.Name("toggleOverlay")
    static let clearResponse  = Notification.Name("clearResponse")
    static let newAnswer      = Notification.Name("newAnswer")
    static let answerToken    = Notification.Name("answerToken")
    static let answerDone     = Notification.Name("answerDone")
    static let whisperLoading = Notification.Name("whisperLoading")
    static let whisperReady   = Notification.Name("whisperReady")
    static let toggleMic      = Notification.Name("toggleMic")
    static let micMuted       = Notification.Name("micMuted")
    static let micUnmuted     = Notification.Name("micUnmuted")
}
