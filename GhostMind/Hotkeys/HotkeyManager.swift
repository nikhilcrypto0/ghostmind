import KeyboardShortcuts
import Foundation

extension KeyboardShortcuts.Name {
    static let toggleHUD     = Self("toggleHUD",     default: .init(.space, modifiers: [.command, .shift]))
    static let clearResponse = Self("clearResponse", default: .init(.x,     modifiers: [.command, .shift]))
    static let manualTrigger = Self("manualTrigger", default: .init(.c,     modifiers: [.command, .shift]))
    static let toggleMic     = Self("toggleMic",     default: .init(.m,     modifiers: [.command, .shift]))
}

class HotkeyManager {
    static let shared = HotkeyManager()

    func register() {
        KeyboardShortcuts.onKeyUp(for: .toggleHUD) {
            NotificationCenter.default.post(name: .toggleOverlay, object: nil)
        }

        KeyboardShortcuts.onKeyUp(for: .clearResponse) {
            NotificationCenter.default.post(name: .clearResponse, object: nil)
        }

        KeyboardShortcuts.onKeyUp(for: .toggleMic) {
            NotificationCenter.default.post(name: .toggleMic, object: nil)
        }

        // ⌘⇧C — Assist: answer the current transcript
        KeyboardShortcuts.onKeyUp(for: .manualTrigger) {
            let transcript = TranscriptionManager.shared.currentTranscript()
            guard !transcript.isEmpty else {
                NotificationCenter.default.post(name: .answerToken, object: nil,
                    userInfo: ["token": "No speech detected yet. Speak a question first."])
                NotificationCenter.default.post(name: .answerDone, object: nil)
                return
            }
            AgentRouter.shared.handle(transcript: transcript, mode: .assist)
        }
    }
}
