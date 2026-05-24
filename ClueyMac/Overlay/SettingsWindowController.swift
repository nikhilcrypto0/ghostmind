import AppKit
import SwiftUI
import ServiceManagement

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Interview Context"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        window.isMovableByWindowBackground = true
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        self.init(window: window)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @State private var jobText: String = ContextManager.shared.jobDescription
    @State private var resumeText: String = ContextManager.shared.resumeSummary
    @State private var captureSystemAudio: Bool = ContextManager.shared.captureSystemAudio
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Interview Context")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Claude tailors every answer to this context")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().background(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    contextField(
                        label: "Job Description",
                        hint: "Paste the full job posting — Claude uses this to tailor every answer to the role",
                        text: $jobText,
                        height: 130
                    ) { ContextManager.shared.jobDescription = jobText }

                    contextField(
                        label: "Your Background",
                        hint: "Paste key resume bullets or a short bio — answers will reference your actual experience",
                        text: $resumeText,
                        height: 130
                    ) { ContextManager.shared.resumeSummary = resumeText }

                    // System audio toggle
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $captureSystemAudio) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Capture interviewer audio")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                Text("Transcribes audio from Zoom, Meet, Teams etc. Requires Screen Recording permission.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .toggleStyle(.switch)
                        .onChange(of: captureSystemAudio) { _, newValue in
                            ContextManager.shared.captureSystemAudio = newValue
                            if newValue { SystemAudioCapture.shared.start() }
                            else        { SystemAudioCapture.shared.stop() }
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Launch at login
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $launchAtLogin) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Launch at login")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                Text("GhostMind starts automatically when you log in to your Mac.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, newValue in
                            try? newValue
                                ? SMAppService.mainApp.register()
                                : SMAppService.mainApp.unregister()
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(20)
            }
        }
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
        .frame(width: 520, height: 460)
    }

    private func contextField(
        label: String,
        hint: String,
        text: Binding<String>,
        height: CGFloat,
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            Text(hint)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))

            TextEditor(text: text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .frame(height: height)
                .onChange(of: text.wrappedValue) { _, _ in onSave() }
        }
    }
}
