import AppKit
import SwiftUI

class SetupWindowController: NSWindowController {
    var onComplete: (() -> Void)?

    convenience init(onComplete: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to GhostMind"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1)
        window.isMovableByWindowBackground = true
        window.center()
        self.init(window: window)
        self.onComplete = onComplete
        window.contentView = NSHostingView(rootView: SetupView(onComplete: onComplete))
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SetupView: View {
    var onComplete: () -> Void

    @State private var anthropicKey: String = ""
    @State private var deepgramKey: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String = ""

    private var canContinue: Bool {
        anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 &&
        deepgramKey.trimmingCharacters(in: .whitespacesAndNewlines).count > 20
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(Color(red: 0.4, green: 0.45, blue: 1.0))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GhostMind")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Text("Invisible AI assistant for interviews")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                .padding(.bottom, 4)

                Text("To get started, add your two free API keys below. These are saved locally on your Mac — never sent anywhere.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .padding(.bottom, 4)

            Divider().background(Color.white.opacity(0.07))

            // Key fields
            VStack(spacing: 20) {
                keyField(
                    number: "1",
                    title: "Anthropic API Key",
                    subtitle: "Powers the AI answers — Claude Haiku",
                    linkLabel: "Get free key at console.anthropic.com →",
                    linkURL: "https://console.anthropic.com/",
                    placeholder: "sk-ant-api03-...",
                    text: $anthropicKey
                )

                keyField(
                    number: "2",
                    title: "Deepgram API Key",
                    subtitle: "Powers speech-to-text — Nova-2 model",
                    linkLabel: "Get free key at console.deepgram.com →",
                    linkURL: "https://console.deepgram.com/",
                    placeholder: "2cad0f0...",
                    text: $deepgramKey
                )

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            Spacer()

            // Footer
            Divider().background(Color.white.opacity(0.07))
            HStack {
                Text("Keys saved locally — never uploaded anywhere")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                Button(action: save) {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Text(isSaving ? "Starting..." : "Get Started →")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(canContinue ? Color(red: 0.35, green: 0.4, blue: 1.0) : Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!canContinue || isSaving)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .frame(width: 480, height: 540)
        .onAppear { loadExistingKeys() }
    }

    private func keyField(
        number: String, title: String, subtitle: String,
        linkLabel: String, linkURL: String,
        placeholder: String, text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(number)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.4, green: 0.45, blue: 1.0))
                    .frame(width: 18, height: 18)
                    .background(Color(red: 0.4, green: 0.45, blue: 1.0).opacity(0.15))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                Button(action: { NSWorkspace.shared.open(URL(string: linkURL)!) }) {
                    Text(linkLabel)
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0.4, green: 0.45, blue: 1.0))
                }
                .buttonStyle(.plain)
            }

            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private func loadExistingKeys() {
        let home = NSHomeDirectory()
        if let k = try? String(contentsOfFile: home + "/.ghostmind_api_key", encoding: .utf8) {
            anthropicKey = k.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let k = try? String(contentsOfFile: home + "/.deepgram_api_key", encoding: .utf8) {
            deepgramKey = k.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func save() {
        let ak = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let dk = deepgramKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ak.isEmpty, !dk.isEmpty else { return }

        isSaving = true
        errorMessage = ""

        let home = NSHomeDirectory()
        do {
            try ak.write(toFile: home + "/.ghostmind_api_key",    atomically: true, encoding: .utf8)
            try dk.write(toFile: home + "/.deepgram_api_key", atomically: true, encoding: .utf8)
            // Expose to GUI-launched processes immediately
            setenv("ANTHROPIC_API_KEY", ak, 1)
            setenv("DEEPGRAM_API_KEY",  dk, 1)
        } catch {
            isSaving = false
            errorMessage = "Could not save keys: \(error.localizedDescription)"
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.keyWindow?.close()
            onComplete()
        }
    }
}
