import AppKit
import SwiftUI

class OverlayWindowController: NSWindowController {
    private var hudViewModel = HUDViewModel()

    convenience init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 440
        let height: CGFloat = 620
        let margin: CGFloat = 20
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

        let viewModel = HUDViewModel()
        let hostingView = NSHostingView(rootView: HUDView(viewModel: viewModel))
        window.contentView = hostingView

        self.init(window: window)
        self.hudViewModel = viewModel

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleAnswerToken(_:)),   name: .answerToken,      object: nil)
        nc.addObserver(self, selector: #selector(handleNewAnswer(_:)),     name: .newAnswer,        object: nil)
        nc.addObserver(self, selector: #selector(handleAnswerDone),        name: .answerDone,       object: nil)
        nc.addObserver(self, selector: #selector(handleWhisperLoading),    name: .whisperLoading,   object: nil)
        nc.addObserver(self, selector: #selector(handleWhisperReady(_:)),  name: .whisperReady,     object: nil)
        nc.addObserver(self, selector: #selector(handleTranscribing),      name: .audioTranscribing,object: nil)
        nc.addObserver(self, selector: #selector(handleTranscriptUpdate(_:)),name: .transcriptUpdate,object: nil)
        nc.addObserver(self, selector: #selector(handleAudioLevel(_:)),    name: .audioLevel,       object: nil)
        nc.addObserver(self, selector: #selector(handleQuestionType(_:)),  name: .questionTypeDetected, object: nil)
        nc.addObserver(self, selector: #selector(handleMicMuted),          name: .micMuted,             object: nil)
        nc.addObserver(self, selector: #selector(handleMicUnmuted),        name: .micUnmuted,           object: nil)
    }

    func toggle() {
        guard let window else { return }
        if window.isVisible { window.orderOut(nil) } else { window.makeKeyAndOrderFront(nil) }
    }

    func clear() { DispatchQueue.main.async { self.hudViewModel.clear() } }

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

    @objc private func handleTranscribing() {
        // no-op: transcribing state removed, listening covers this
    }

    @objc private func handleTranscriptUpdate(_ n: Notification) {
        guard let text = n.userInfo?["text"] as? String else { return }
        DispatchQueue.main.async {
            self.hudViewModel.liveTranscript = String(text.suffix(120))
        }
    }

    @objc private func handleAudioLevel(_ n: Notification) {
        guard let level = n.userInfo?["level"] as? Float else { return }
        DispatchQueue.main.async { self.hudViewModel.audioLevel = level }
    }

    @objc private func handleMicMuted() {
        DispatchQueue.main.async { self.hudViewModel.micStatus = .muted }
    }

    @objc private func handleMicUnmuted() {
        DispatchQueue.main.async { self.hudViewModel.micStatus = .listening }
    }

    @objc private func handleQuestionType(_ n: Notification) {
        // questionType now embedded in AssistMode — no separate state needed
    }
}
