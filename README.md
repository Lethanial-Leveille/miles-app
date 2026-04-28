# Nova

**Native SwiftUI companion app for [M.I.L.E.S.](https://github.com/Lethanial-Leveille/miles), a voice AI assistant running on a Raspberry Pi 5.**

Nova is the remote interface for M.I.L.E.S. (Modular Intelligent Learning and Execution System). The Pi handles voice, wake word detection, speaker verification, and TTS in my room. Nova lets me talk to it from anywhere in the world.

Built from scratch in Swift with zero third party dependencies.

---

## Demo

Watch the full demo on LinkedIn: [linkedin.com/in/lethanial-lee-leveille](https://www.linkedin.com/in/lethanial-lee-leveille)

---

## Features

- **Face ID authentication** with JWT stored in iOS Keychain
- **Real time chat** with Nova via REST POST to the Pi backend
- **On device speech input** via SFSpeechRecognizer with auto stop on silence
- **Paginated conversation history** with client side keyword search
- **Memory bank viewer** for inspecting what Nova remembers
- **System status monitoring** for the Pi backend
- **Auto logout on JWT expiry** with seamless return to login screen
- **Custom Nova design system** in electric blue, off white, and pure black

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI Framework | SwiftUI (iOS 17+) |
| Concurrency | Swift async/await, MainActor isolation |
| Networking | URLSession with custom APIClient wrapper |
| Auth | JWT (HS256, 7 day tokens), iOS Keychain Services |
| Biometrics | LocalAuthentication framework (Face ID) |
| Speech Recognition | SFSpeechRecognizer (on device) |
| State Management | ObservableObject + @StateObject + @EnvironmentObject |
| Theme System | Custom Theme.swift design tokens, forced dark mode |
| Dependencies | None |

---

## Architecture

### Auth Flow

```
LoginView
   └─> AuthManager (ObservableObject)
          └─> Keychain (token storage)
          └─> APIClient (auth header injection)
                 └─> 401 callback → AuthManager.handleUnauthorized()
                        └─> isAuthenticated = false
                               └─> SwiftUI auto routes back to LoginView
```

`AuthManager` owns `@Published var isAuthenticated`. Any 401 response from the Pi triggers `handleUnauthorized()`, which clears the Keychain token and flips the bool. SwiftUI handles the rest automatically through the environment object pattern.

### App Structure

```
NovaApp
   └─> AuthManager (@StateObject, injected as environmentObject)
          ├─ LoginView (when !isAuthenticated)
          └─ MainTabView (when isAuthenticated)
                 ├─ ChatView (REST POST /chat, speech input via SFSpeechRecognizer)
                 ├─ HistoryView (paginated, client side search)
                 └─ SettingsView
                        ├─ System Status (live ping to /status)
                        ├─ Memory Bank (push to MemoriesView)
                        ├─ Voice settings (auto send toggle)
                        ├─ About
                        └─ Logout
```

### Backend Communication

Nova talks to the Pi backend at `https://miles.lethanial.com` over HTTPS via Cloudflare Tunnel. Endpoints used:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/auth/login` | POST | Initial JWT issue |
| `/auth/refresh` | POST | Token refresh |
| `/chat` | POST | Send message, receive Nova's response |
| `/memories` | GET | Fetch what Nova remembers |
| `/memories/{id}` | DELETE | Remove a memory |
| `/history` | GET | Paginated conversation log |
| `/status` | GET | Backend health and version |

---

## Design System

Nova uses a strict three color palette enforced via `Theme.swift`:

- **Background**: `#0A0A0A` (near pure black)
- **Surface**: slightly lifted dark for cards
- **Accent**: `#00E5FF` (electric cyan blue, the only chromatic color)
- **Text Primary**: off white
- **Text Secondary**: muted gray

Forced dark mode via `.preferredColorScheme(.dark)` at the app root. No light mode support, intentional.

The app icon is a custom voice waveform mark (six electric blue bars on pure black) generated programmatically and exported to all required iOS icon sizes.

---

## Project Structure

```
Nova/
├── NovaApp.swift              # App entry, auth state routing
├── Theme.swift                # Color and typography tokens
├── Constants.swift            # API base URL, keychain keys
│
├── Auth/
│   ├── AuthManager.swift      # ObservableObject, owns isAuthenticated
│   ├── KeychainHelper.swift   # iOS Keychain wrapper
│   └── LoginView.swift        # Animated waveform + Face ID + password
│
├── Networking/
│   ├── APIClient.swift        # URLSession wrapper, JWT injection, 401 handling
│   └── Models/                # Codable structs for API responses
│
├── Views/
│   ├── MainTabView.swift      # 3 tab bottom nav
│   ├── ChatView.swift         # Message list, composer, mic button
│   ├── MessageBubble.swift    # Speaker labels, emotion tag stripping
│   ├── HistoryView.swift      # Pagination + search
│   ├── SettingsView.swift     # Status, memories, voice, logout
│   └── MemoriesView.swift     # Memory bank list
│
└── Services/
    └── SpeechService.swift    # SFSpeechRecognizer wrapper, on device only
```

---

## Notable Engineering Decisions

**No third party dependencies.** Every line in this app is either Swift standard library or Apple framework. This was a deliberate constraint to deepen Swift fluency and avoid SPM/CocoaPods overhead for a single developer project.

**On device speech recognition only.** `SFSpeechRecognizer` is configured with `requiresOnDeviceRecognition = true` so transcription happens locally without sending audio to Apple's servers. Privacy and offline capability.

**JWT stored in Keychain, not UserDefaults.** Using iOS Keychain Services for secure token storage. UserDefaults is plaintext and trivially extracted from a backed up phone.

**ObservableObject + EnvironmentObject for auth state.** A single AuthManager instance is injected at the app root and observed by every view that cares about auth state. When the token expires server side, the 401 response triggers a single state mutation that propagates through the entire view hierarchy automatically.

**REST over WebSocket for chat.** Originally tried WebSocket but discovered the Pi backend's `/chat` returns JSON via REST faster than the WebSocket round trip. WebSocket is reserved for future streaming responses.

---

## Running Locally

This app requires the M.I.L.E.S. Pi backend running and accessible. To run Nova on your own setup:

1. Clone the repo: `git clone https://github.com/Lethanial-Leveille/miles-app.git`
2. Open `Nova.xcodeproj` in Xcode 15 or later
3. Update `Constants.swift` to point to your own backend URL
4. Build and run on a physical iPhone (Face ID requires real hardware)

The Pi backend code lives at [github.com/Lethanial-Leveille/miles](https://github.com/Lethanial-Leveille/miles).

---

## Roadmap

- [ ] Speech output: stream Emma's voice from Pi to phone via WebSocket for full voice conversations through the app
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
