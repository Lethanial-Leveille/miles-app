# Nova

**Native SwiftUI companion app for [M.I.L.E.S.](https://github.com/Lethanial-Leveille/miles), a voice AI assistant running on a Raspberry Pi 5.**

Nova is the remote interface for M.I.L.E.S. (Modular Intelligent Learning and Execution System). The Pi handles voice, wake word detection, speaker verification, and TTS in my room. Nova lets me talk to it from anywhere in the world, by typing or out loud.

Built from scratch in Swift with zero third party dependencies.

---

## Demo

Watch the full demo on LinkedIn: [linkedin.com/in/lethanial-lee-leveille](https://www.linkedin.com/in/lethanial-lee-leveille)

---

## Features

- **Talk Mode**: a full screen spoken conversation. Nova listens, answers in the same ElevenLabs voice she uses in my room, then listens again. A six bar waveform follows my voice while she listens and hers while she speaks. Tap to send early or to cut her off.
- **Streaming chat** over Server Sent Events. Replies appear as they are written, and while a tool runs the indicator says what she is doing ("Checking your calendar").
- **Markdown replies** rendered by a parser written for this app: headings, nested lists, quotes, code blocks and tables.
- **One conversation across devices**: chat opens on the last 20 messages, including what was said out loud in the room, marked with a speaker icon.
- **Face ID login that survives token expiry**, with 60 minute JWTs renewed quietly in the background.
- **On device speech input** via SFSpeechRecognizer with auto stop after 2 seconds of silence.
- **Memory Bank**: review memories Nova inferred on her own (approve or reject), add new ones, and edit them with the full wording history kept.
- **Your week**: seven days of Google Calendar, with events on Nova's own calendar editable in place.
- **Reminders and timers** with live countdowns and swipe to cancel.
- **Diagnostics** for the Pi: uptime, core temperature, response latency, and whether each backend service is running.
- **Conversation history** grouped by day, with search and pull to refresh.
- **Dynamic Type** throughout, and a custom design system in electric blue, off white, and black.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI Framework | SwiftUI (iOS 17.6+) |
| Concurrency | Swift async/await, MainActor by default |
| Networking | URLSession, with `bytes(for:)` for Server Sent Events |
| Auth | JWT (HS256, 60 minute tokens renewed through `/auth/refresh`), iOS Keychain Services |
| Biometrics | LocalAuthentication, plus a Keychain item gated by `.biometryCurrentSet` |
| Speech Recognition | SFSpeechRecognizer (on device) with AVAudioEngine |
| Voice Playback | AVAudioPlayer, mp3 synthesized on the Pi |
| State Management | ObservableObject + @StateObject + @EnvironmentObject |
| Theme System | Custom Theme.swift design tokens, forced dark mode |
| Dependencies | None |

---

## Architecture

### Auth Flow

```
LoginView
   └─> AuthManager (ObservableObject)
          └─> AuthService (login, renewal, Keychain)
          └─> APIService (auth header injection)
                 └─> 401 callback → AuthManager.handleUnauthorized()
                        └─> isAuthenticated = false
                               └─> SwiftUI auto routes back to LoginView
```

`AuthManager` owns `@Published var isAuthenticated`. Any 401 from the Pi triggers `handleUnauthorized()`, which clears the token and flips the bool, and SwiftUI returns to the login screen through the environment object.

The backend has no refresh token, only access tokens that last an hour. So the app renews a token during its last 10 minutes, and a password login also stores the password in a Keychain item that only Face ID can unlock. When the hour does run out, Face ID reads it and logs in fresh, and the user never types the password again.

### Talk Mode

```
TalkSession loop
   ├─ listen   SpeechService.listen()  →  one utterance, ended by 2s of silence or a tap
   ├─ send     ChatService.send(channel: .voice)  →  POST /chat/stream
   ├─ speak    POST /speak with the finished reply  →  mp3  →  VoicePlayer
   └─ repeat until closed
```

The `voice` channel asks Nova to write for the ear: no markdown, symbols spelled out. Every turn goes through the same `ChatService` as typing, so a spoken conversation is in the chat afterwards.

### App Structure

```
NovaApp
   └─> AuthManager (@StateObject, injected as environmentObject)
          ├─ LoginView (when !isAuthenticated)
          └─ MainTabView (when isAuthenticated)
                 ├─ ChatView (streamed chat, speech input)
                 │      └─ TalkView (full screen Talk Mode)
                 ├─ HistoryView (grouped by day, search)
                 └─ SettingsView
                        ├─ SystemView (diagnostics)
                        ├─ MemoriesView → MemoryDetailView
                        ├─ CalendarView (your week)
                        ├─ RemindersView
                        ├─ Voice settings (auto send toggle)
                        ├─ About
                        └─ Logout
```

### Backend Communication

Nova talks to the Pi at `https://miles.lethanial.com` over HTTPS through a Cloudflare Tunnel.

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/auth/login`, `/auth/refresh` | POST | Issue and renew the JWT |
| `/chat/stream` | POST | A chat turn as Server Sent Events |
| `/chat` | POST | The same turn in one response, the fallback |
| `/speak` | POST | A finished reply as mp3 in Nova's voice |
| `/history` | GET | Paginated conversation log |
| `/memories`, `/memories/pending` | GET | Active memories and ones awaiting approval |
| `/memories`, `/memories/{id}` | POST, PATCH, DELETE | Add, edit, remove |
| `/memories/{id}/approve`, `/memories/{id}/history` | POST, GET | Approve, and wording history |
| `/calendar/events`, `/calendar/events/{id}` | GET, PATCH, DELETE | The week, and edits to Nova's events |
| `/reminders`, `/reminders/{id}` | GET, DELETE | Open reminders and timers |
| `/status`, `/status/details` | GET | Connection check and diagnostics |

---

## Design System

Nova uses a strict palette enforced via `Theme.swift`:

- **Background**: `#0A0B10` (near black)
- **Surface**: slightly lifted dark for cards
- **Accent**: `#00E5FF` (electric cyan blue, the only chromatic color)
- **Text Primary**: off white
- **Text Secondary**: muted gray

There is no red anywhere, not even for delete actions, and state is shown by shape rather than color: a service that is down is a hollow dot and the word DOWN. Dark mode is forced via `.preferredColorScheme(.dark)`, intentionally. Every font goes through a `novaFont` modifier that scales with Dynamic Type.

The app icon is a custom voice waveform mark (six electric blue bars on pure black), and the same six bars animate on the login screen and in Talk Mode.

---

## Project Structure

```
Nova/
├── NovaApp.swift              # App entry, auth state routing
│
├── Views/
│   ├── LoginView.swift        # Animated waveform, Face ID, password
│   ├── MainTabView.swift      # Chat, History, Settings
│   ├── ChatView.swift         # Streamed chat, composer, mic, Talk Mode button
│   ├── TalkView.swift         # Full screen Talk Mode
│   ├── HistoryView.swift      # Grouped by day, search
│   ├── SettingsView.swift     # Entry point for every screen below
│   ├── SystemView.swift       # Diagnostics
│   ├── MemoriesView.swift     # Memory Bank, approval queue
│   ├── MemoryDetailView.swift # One memory and its wording history
│   ├── CalendarView.swift     # Your week, event editor
│   └── RemindersView.swift    # Reminders and live timers
│
├── Components/
│   ├── MessageBubble.swift    # YOU and NOVA bubbles
│   ├── MarkdownText.swift     # Renders parsed markdown blocks
│   ├── NovaTypingIndicator.swift
│   ├── TalkWaveform.swift     # The six bars, driven by audio level
│   ├── MemoryEditor.swift
│   └── ScreenHeader.swift
│
├── Services/
│   ├── APIService.swift       # Every route, SSE parsing, 401 handling
│   ├── AuthManager.swift      # ObservableObject, owns isAuthenticated
│   ├── AuthService.swift      # Login, renewal, Face ID
│   ├── ChatService.swift      # A chat turn, streamed or blocking
│   ├── SpeechService.swift    # SFSpeechRecognizer, on device only
│   ├── TalkSession.swift      # The Talk Mode loop
│   └── VoicePlayer.swift      # Plays Nova's voice, awaitable
│
├── Models/                    # Codable structs for API responses
│
└── Utilities/
    ├── Theme.swift            # Color tokens
    ├── ScaledFont.swift       # novaFont, Dynamic Type
    ├── MarkdownParser.swift   # Markdown to blocks, Foundation only
    ├── KeychainHelper.swift   # Keychain wrapper, biometry gated items
    ├── ServerDate.swift       # The backend's timestamps
    └── Constants.swift        # API base URL, Keychain keys
```

---

## Notable Engineering Decisions

**No third party dependencies.** Every line in this app is either Swift standard library or Apple framework, including the markdown parser. This was a deliberate constraint to deepen Swift fluency and avoid SPM/CocoaPods overhead for a single developer project.

**One voice, synthesized once.** Nova's voice runs on ElevenLabs `eleven_v3`, which voices every request on its own. Sending a reply one sentence at a time would start audio sooner, but she comes back sounding like a different speaker partway through. So Talk Mode waits for the finished reply and asks for it whole. It costs about a second before she starts, and she sounds like herself.

**A turn that started is never retried.** A chat turn can create calendar events or set timers, and the Pi finishes it even if the phone loses the connection. Sending it again would run those tools twice. So only a stream that never opened falls back to the blocking route, and closing Talk Mode mid turn still lets the reply land in the chat.

**Streaming with a reset.** When Nova calls a tool, the sentence she wrote beforehand is not part of the answer. The stream sends a `reset` event, and the app drops that bubble and starts the reply over rather than showing text that never makes it into history.

**On device speech recognition only.** `SFSpeechRecognizer` is configured with `requiresOnDeviceRecognition = true`, so transcription happens locally without sending audio to Apple's servers.

**Secrets in the Keychain, not UserDefaults.** The token lives in the Keychain, and the stored password sits behind `.biometryCurrentSet`, so enrolling a new face or fingerprint invalidates it.

**The backend's clock, read as it is.** The Pi stores timestamps in local time with no offset. They are kept as strings and parsed as local time in one place, `ServerDate`, instead of pretending they are UTC.

---

## Running Locally

This app requires the M.I.L.E.S. Pi backend running and reachable.

1. Clone the repo: `git clone https://github.com/Lethanial-Leveille/miles-app.git`
2. Open `Nova.xcodeproj` in Xcode 16 or later
3. Under Signing & Capabilities, pick your own team and change the bundle identifier
4. Update `Nova/Utilities/Constants.swift` to point to your own backend URL
5. Build and run on a physical iPhone (Face ID and on device speech need real hardware)

The Pi backend code lives at [github.com/Lethanial-Leveille/miles](https://github.com/Lethanial-Leveille/miles).

---

## Roadmap

- [x] Speech output: full voice conversations through the app (Talk Mode)
- [ ] Voice barge in: interrupt Nova by speaking over her, not just by tapping
- [ ] Tiered voice security: multi user permission system using voice embeddings
- [ ] iPad layout polish via NavigationSplitView
- [ ] Mac Catalyst support
- [ ] Apple Watch companion target
- [ ] Apple Health integration for morning briefing context

---

## About

Built by Lethanial Leveille, Computer Engineering student at the University of Florida, Class of 2029. Targeting embedded and firmware engineering.

- Portfolio: [lethanial.com](https://lethanial.com) (under construction)
- LinkedIn: [linkedin.com/in/lethanial-lee-leveille](https://www.linkedin.com/in/lethanial-lee-leveille)
- Email: leveillelethanial@gmail.com

---

## License

Personal project. Code is provided as is for portfolio review purposes.
