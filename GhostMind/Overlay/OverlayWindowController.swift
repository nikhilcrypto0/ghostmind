import AppKit
import SwiftUI

class OverlayWindowController: NSWindowController {
    // Initialized at declaration so notification handlers can fire safely
    // even before convenience init completes assigning observers.
    private let hudViewModel = HUDViewModel()

    convenience init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width = AppConfig.hudWidth
        let height = AppConfig.hudHeight
        let margin = AppConfig.hudMargin
        let rect = NSRect(
            x: screen.visibleFrame.maxX - width - margin,
            y: screen.visibleFrame.maxY - height - margin,
            width: width,
            height: height
        )

        let window = OverlayWindow(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)

        // NSHostingController + preferredContentSize makes the window resize to
        // match the SwiftUI HUD's intrinsic content height. When the HUD collapses
        // (no answer streaming), the window shrinks too — so clicks in the area
        // beneath the HUD pass through to whatever app sits there.
        let hosting = NSHostingController(rootView: HUDView(viewModel: hudViewModel))
        hosting.sizingOptions = [.preferredContentSize]
        window.contentViewController = hosting

        anchorTopRight()
        window.makeKeyAndOrderFront(nil)

        let nc = NotificationCenter.default
        // Live observers — these all drive HUDViewModel state.
        nc.addObserver(self, selector: #selector(handleAnswerToken(_:)),   name: .answerToken,    object: nil)
        nc.addObserver(self, selector: #selector(handleNewAnswer(_:)),     name: .newAnswer,      object: nil)
        nc.addObserver(self, selector: #selector(handleAnswerDone),        name: .answerDone,     object: nil)
        nc.addObserver(self, selector: #selector(handleWhisperLoading),    name: .whisperLoading, object: nil)
        nc.addObserver(self, selector: #selector(handleWhisperReady(_:)),  name: .whisperReady,   object: nil)
        nc.addObserver(self, selector: #selector(handleMicMuted),          name: .micMuted,       object: nil)
        nc.addObserver(self, selector: #selector(handleMicUnmuted),        name: .micUnmuted,     object: nil)

        // Re-anchor to the top-right whenever the window resizes (it shrinks when
        // the HUD collapses, grows when an answer streams).
        nc.addObserver(self, selector: #selector(handleWindowResize),
                       name: NSWindow.didResizeNotification, object: window)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func toggle() {
        guard let window else { return }
        if window.isVisible { window.orderOut(nil) } else { window.makeKeyAndOrderFront(nil) }
    }

    func clear() { DispatchQueue.main.async { self.hudViewModel.clear() } }

    private func anchorTopRight() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let margin = AppConfig.hudMargin
        let frame = window.frame
        let newOrigin = NSPoint(
            x: screen.visibleFrame.maxX - frame.width - margin,
            y: screen.visibleFrame.maxY - frame.height - margin
        )
        if window.frame.origin != newOrigin {
            window.setFrameOrigin(newOrigin)
        }
    }

    @objc private func handleWindowResize() {
        anchorTopRight()
    }

    @objc private func handleAnswerToken(_ n: Notification) {
        guard let token = n.userInfo?["token"] as? String else { return }
        DispatchQueue.main.async { self.hudViewModel.appendToken(token) }
    }

    @objc private func handleNewAnswer(_ n: Notification) {
        DispatchQueue.main.async { self.hudViewModel.startNewAnswer() }
    }

    @objc private func handleAnswerDone() {
        DispatchQueue.main.async { self.hudViewModel.finishStreaming() }
    }

    @objc private func handleWhisperLoading() {
        DispatchQueue.main.async { self.hudViewModel.micStatus = .loading }
    }

    @objc private func handleWhisperReady(_ n: Notification) {
        DispatchQueue.main.async {
            if let error = n.userInfo?["error"] as? String {
                self.hudViewModel.micStatus = .error(error)
            } else {
                self.hudViewModel.micStatus = .listening
            }
        }
    }

    @objc private func handleMicMuted() {
        DispatchQueue.main.async { self.hudViewModel.micStatus = .muted }
    }

    @objc private func handleMicUnmuted() {
        DispatchQueue.main.async { self.hudViewModel.micStatus = .listening }
    }
}
