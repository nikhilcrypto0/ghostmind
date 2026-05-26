import SwiftUI

enum MicStatus: Equatable {
    case loading, listening, muted, thinking, error(String)

    var label: String {
        switch self {
        case .loading:       return "Starting..."
        case .listening:     return "Listening"
        case .muted:         return "Muted"
        case .thinking:      return "Thinking..."
        case .error(let m):  return m
        }
    }

    var color: Color {
        switch self {
        case .loading:   return .orange
        case .listening: return .green
        case .muted:     return .red
        case .thinking:  return Color(red: 0.5, green: 0.4, blue: 1.0)
        case .error:     return .red
        }
    }

    var isPulsing: Bool {
        switch self {
        case .listening, .thinking: return true
        default: return false
        }
    }
}

@Observable
class HUDViewModel {
    var currentResponse: String = ""
    var isStreaming: Bool = false
    var micStatus: MicStatus = .loading
    var audioLevel: Float = 0
    var activeMode: String = "Assist"

    func appendToken(_ token: String) {
        currentResponse += token
        isStreaming = true
    }

    func startNewAnswer() {
        currentResponse = ""
        isStreaming = true
        micStatus = .thinking
    }

    func finishStreaming() {
        isStreaming = false
        if micStatus == .thinking { micStatus = .listening }
    }

    func clear() {
        currentResponse = ""
        isStreaming = false
        if micStatus == .thinking { micStatus = .listening }
    }
}

struct HUDView: View {
    @State var viewModel: HUDViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            VStack(spacing: 0) {
                topBar
                Divider().background(Color.white.opacity(0.08))
                responseArea
                Divider().background(Color.white.opacity(0.08))
                actionButtons
            }
        }
        .frame(width: AppConfig.hudWidth)
        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 8)
    }

    // MARK: — Top bar (minimal: status dot · mic toggle · close)

    private var topBar: some View {
        HStack(spacing: 10) {
            statusDot
            Spacer()
            contextButton
            micButton
            clearButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var contextButton: some View {
        Button(action: { SettingsWindowController.shared.show() }) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
        }
        .buttonStyle(.plain)
        .help("Interview Context (JD + Background)")
    }

    private var statusDot: some View {
        ZStack {
            if viewModel.micStatus.isPulsing {
                Circle()
                    .fill(viewModel.micStatus.color.opacity(0.25))
                    .frame(width: 14, height: 14)
                    .scaleEffect(1.3)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                               value: viewModel.micStatus.isPulsing)
            }
            Circle()
                .fill(viewModel.micStatus.color)
                .frame(width: 7, height: 7)
        }
        .help(viewModel.micStatus.label)
    }

    private var micButton: some View {
        Button(action: { NotificationCenter.default.post(name: .toggleMic, object: nil) }) {
            Image(systemName: viewModel.micStatus == .muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 12))
                .foregroundColor(viewModel.micStatus == .muted ? .red : .white.opacity(0.5))
        }
        .buttonStyle(.plain)
        .help("Mute mic (⌘⇧M)")
    }

    private var clearButton: some View {
        Button(action: { viewModel.clear() }) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .buttonStyle(.plain)
        .help("Clear (⌘⇧X)")
    }

    // MARK: — Response area

    private var responseArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    if viewModel.currentResponse.isEmpty && !viewModel.isStreaming {
                        emptyState
                    } else {
                        Text(viewModel.currentResponse + (viewModel.isStreaming ? "▋" : ""))
                            .font(.system(size: 13.5))
                            .foregroundColor(.white.opacity(0.92))
                            .textSelection(.enabled)
                            .lineSpacing(3)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Scroll to top when a new answer starts — user reads from beginning
            .onChange(of: viewModel.isStreaming) { _, streaming in
                if streaming { proxy.scrollTo("top", anchor: .top) }
            }
        }
        .frame(minHeight: 90, maxHeight: 280)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.2))
            Text("Listening for questions...")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
            Text("Auto-detects questions · or use the buttons below")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: — Action buttons

    private var actionButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                modeButton(icon: "sparkles", label: "Assist", mode: .assist(.behavioral)) {
                    let t = TranscriptionManager.shared.currentTranscript()
                    let type = QuestionDetector.shared.analyze(transcript: t)?.type ?? .behavioral
                    fireMode(.assist(type), transcript: t)
                }
                modeSeparator
                modeButton(icon: "text.bubble", label: "What should I say?", mode: .whatToSay) {
                    fireMode(.whatToSay, transcript: TranscriptionManager.shared.currentTranscript())
                }
                modeSeparator
                modeButton(icon: "list.bullet", label: "Follow-up questions", mode: .followUp) {
                    fireMode(.followUp, transcript: TranscriptionManager.shared.currentTranscript())
                }
                modeSeparator
                modeButton(icon: "arrow.clockwise", label: "Recap", mode: .recap) {
                    fireMode(.recap, transcript: TranscriptionManager.shared.currentTranscript())
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 2)
    }

    private var modeSeparator: some View {
        Text("·")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.2))
            .padding(.horizontal, 2)
    }

    private func modeButton(icon: String, label: String, mode: AssistMode, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(viewModel.activeMode == label ? .white : .white.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                viewModel.activeMode == label
                    ? Color.white.opacity(0.12)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func fireMode(_ mode: AssistMode, transcript: String) {
        guard !transcript.isEmpty else {
            viewModel.appendToken("No speech detected yet — speak something first.")
            viewModel.finishStreaming()
            return
        }
        let label: String
        switch mode {
        case .assist:    label = "Assist"
        case .whatToSay: label = "What should I say?"
        case .followUp:  label = "Follow-up questions"
        case .recap:     label = "Recap"
        case .custom:    label = "Custom"
        }
        viewModel.activeMode = label
        viewModel.startNewAnswer()
        AgentRouter.shared.handle(transcript: transcript, mode: mode)
    }

}


struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.material = .hudWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
