# GhostMind

**Invisible AI interview assistant for macOS.**

GhostMind listens to your interview — mic and system audio — transcribes in real-time using Deepgram Nova-2, detects questions automatically, and streams Claude answers into a floating overlay that is **completely invisible to screen sharing** (Zoom, Google Meet, Microsoft Teams).

> macOS only. Requires macOS 14 Sonoma or later.

---

## How it works

```
Mic + System Audio
       ↓
Deepgram Nova-2 (WebSocket, real-time)
       ↓
Question auto-detected (coding / system design / conceptual / behavioral)
       ↓
Claude Haiku streams the answer
       ↓
Floating HUD overlay — invisible to screen capture APIs
```

---

## Features

- **Invisible overlay** — uses `NSWindowSharingNone` so the panel never appears in any screen recording or share
- **Dual audio** — captures your mic AND the interviewer's voice from Zoom/Meet/Teams via ScreenCaptureKit
- **Auto question detection** — no need to press anything; questions trigger answers automatically
- **Question-type aware** — coding questions get code, system design gets architecture, conceptual gets direct explanations, behavioral gets STAR format
- **Conversation memory** — rolling 8000-char transcript so Claude can reference earlier exchanges
- **Interview context** — paste your job description and resume; every answer is tailored to the role
- **Deepgram Nova-2** transcription with Apple Speech fallback (no Deepgram key needed to start)
- **Launch at login** via SMAppService

---

## Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 14 Sonoma or later |
| Xcode / Swift | Swift 5.9+ (Xcode 15+) |
| Anthropic API key | [console.anthropic.com](https://console.anthropic.com/) |
| Deepgram API key *(optional but recommended)* | [console.deepgram.com](https://console.deepgram.com/) |

Both API keys have free tiers that are sufficient for interview use.

---

## Install

```bash
git clone https://github.com/nikhilcrypto0/ghostmind.git
cd ghostmind
bash install.sh
```

The installer:
1. Builds a release binary with `swift build`
2. Creates `GhostMind.app` in `/Applications`
3. Code-signs and launches the app

On first launch, a setup window will ask for your API keys. They are saved locally to `~/.ghostmind_api_key` and `~/.deepgram_api_key` — never sent anywhere except directly to Anthropic and Deepgram.

---

## Permissions required

| Permission | Why |
|------------|-----|
| Microphone | Captures your voice |
| Screen Recording | Captures interviewer audio from video call apps |
| Speech Recognition | Apple Speech fallback (no Deepgram key) |

Grant these in **System Settings → Privacy & Security** when prompted.

---

## Hotkeys

| Shortcut | Action |
|----------|--------|
| `⌘ ⇧ Space` | Show / hide the overlay |
| `⌘ ⇧ X` | Clear the current response |

---

## Menu bar

Click the **brain icon** in the menu bar to access:
- Show / Hide overlay
- Interview Context (job description + resume)
- Launch at Login toggle
- Clear Response
- Quit

---

## Interview Context

Open **Interview Context** from the menu bar and paste:
- **Job Description** — Claude tailors every answer to the role
- **Your Background** — Claude references your actual experience

Both fields auto-save as you type.

---

## Architecture

```
GhostMind/
├── App/
│   ├── AppDelegate.swift          # App lifecycle, menu bar, hotkeys
│   └── SetupWindowController.swift # First-run API key setup
├── Audio/
│   ├── AudioCaptureManager.swift  # AVAudioEngine mic tap
│   ├── SystemAudioCapture.swift   # ScreenCaptureKit system audio
│   └── TranscriptionManager.swift # Deepgram WebSocket + Apple Speech fallback
├── Detection/
│   └── QuestionDetector.swift     # Question type classification + cooldown
├── AI/
│   ├── ClaudeClient.swift         # Streaming Claude API client
│   └── PromptTemplates.swift      # Per-question-type system prompts
├── Context/
│   └── ContextManager.swift       # Job description + resume persistence
├── Orchestration/
│   └── AgentRouter.swift          # Routes detected questions to Claude
├── Overlay/
│   ├── HUDView.swift              # SwiftUI answer display
│   ├── OverlayWindow.swift        # NSPanel (screen-share invisible)
│   ├── OverlayWindowController.swift
│   └── SettingsWindowController.swift # Interview context editor
├── Hotkeys/
│   └── HotkeyManager.swift        # Global ⌘⇧Space / ⌘⇧X registration
└── Config/
    ├── AppConfig.swift
    └── GhostLog.swift             # Debug log → ~/ghostmind-debug.log
```

---

## Debugging

Logs are written to `~/ghostmind-debug.log`. Tail it during an interview to see transcription, question detection, and API activity:

```bash
tail -f ~/ghostmind-debug.log
```

---

## Platform support

| Platform | Supported |
|----------|-----------|
| macOS 14+ | ✅ |
| macOS 13 | ⚠️ Partial (no ScreenCaptureKit system audio) |
| Windows | ❌ |
| Linux | ❌ |

GhostMind uses Apple-only frameworks (`AppKit`, `AVFoundation`, `ScreenCaptureKit`, `SMAppService`) that have no cross-platform equivalents. A Windows version would need to be rebuilt from scratch.

---

## License

MIT
