# Nova — iOS Companion App for M.I.L.E.S.

## What This Project Is

Native SwiftUI companion app for M.I.L.E.S. (Modular Intelligent Learning and Execution System), a voice AI assistant running on a Raspberry Pi 5. The app is named Nova (the voice personality name). M.I.L.E.S. is the system name used on the resume and GitHub.

Built by Lethanial Leveille, CpE student at University of Florida, Class of 2029. This is the iOS frontend for the M.I.L.E.S. backend, which is a separate repo at github.com/Lethanial-Leveille/miles.

The backend is already fully built and deployed. This session is ONLY about building the Swift app. Do not suggest changes to the backend.

## Companion Repo Context

The Pi backend exposes a FastAPI server at https://miles.lethanial.com with these endpoints:

REST (all require JWT auth except login):
- POST /auth/login — send password, receive access + refresh tokens
- POST /auth/refresh — exchange refresh token for new access token
- POST /chat — send text message, receive Nova's response as plain text
- GET /memories — list all stored memories
- DELETE /memories/{id} — delete a specific memory
- GET /history — recent conversation history (paginated)
- GET /status — system info (uptime, version, memory count, last interaction)

WebSocket:
- /ws — persistent connection, auth via first message

Auth: JWT, Authorization Bearer header. Access token: 7 day expiry. Refresh token: 30 day expiry. Algorithm: HS256.

WebSocket message format (JSON):
- Auth: {"type": "auth", "token": "eyJhbG..."}
- Server confirms: {"type": "auth_ok"}
- Send message: {"type": "message", "text": "What is the weather?"}
- Receive response: {"type": "response", "text": "[calmly] It is eighty two degrees..."}

Nova's responses may contain bracketed emotion tags like [calmly], [matter of factly], [warmly] at the start. Strip these from displayed text in the UI. They are for TTS only.

## App Overview

The app is a text based interface to Nova. No audio recording or playback in v0.7. Text only. Voice input through the app mic is a future version feature.

The app connects to the Pi over WebSocket for the chat screen and REST for all other screens. When on home WiFi, it connects via miles.lethanial.com (the Cloudflare Tunnel handles routing either way, so there is no need for a separate local WiFi path in v0.7).

## Target File Structure

```
Nova/
├── NovaApp.swift                  # App entry point, handles auth state
├── Models/
│   ├── Message.swift              # Chat message model
│   ├── Memory.swift               # Memory model
│   └── SystemStatus.swift         # Status model
├── Services/
│   ├── AuthService.swift          # Login, token storage (Keychain), refresh
│   ├── APIService.swift           # All REST calls
│   └── WebSocketService.swift     # WebSocket connection management
├── Views/
│   ├── LoginView.swift            # Password entry + FaceID
│   ├── MainTabView.swift          # Bottom tab bar (Chat, Status, Memories, History)
│   ├── ChatView.swift             # Main conversation interface
│   ├── StatusView.swift           # System dashboard
│   ├── MemoriesView.swift         # View and delete memories
│   └── HistoryView.swift          # Browse past conversations
├── Components/
│   ├── MessageBubble.swift        # Chat bubble component
│   └── NovaTypingIndicator.swift  # Animated typing indicator while waiting
└── Utilities/
    ├── KeychainHelper.swift       # Keychain read/write wrapper
    └── Constants.swift            # API base URL, token keys
```

## Build Order

Build in this order. Each step produces something testable before moving on.

1. Constants.swift and KeychainHelper.swift (foundation, no UI)
2. AuthService.swift (login, token storage, refresh logic)
3. LoginView.swift (first screen, test login end to end)
4. APIService.swift (REST calls, test with /status endpoint)
5. WebSocketService.swift (WebSocket connection and messaging)
6. ChatView.swift (main screen, connect WebSocket, send and receive messages)
7. StatusView.swift (dashboard)
8. MemoriesView.swift (list and delete)
9. HistoryView.swift (browsing history)
10. MainTabView.swift (wire all screens together with tab bar)
11. NovaApp.swift (auth state logic, show LoginView vs MainTabView)
12. FaceID integration into LoginView (LocalAuthentication framework)
13. Polish (colors, typography, spacing, dark mode)

## Design Direction

Dark theme. The Pi is a black device, Nova is a voice AI. The app should feel like a control panel, not a social app. Think dark background, subtle blue or white accents, clean typography, no clutter.

Reference: think of how a Bloomberg terminal or a technical dashboard feels. Serious, precise, information dense but readable.

Specific direction:
- Background: near black (not pure black, something like #0A0A0F)
- Accent: cool blue (#4A9EFF or similar) for interactive elements
- Nova's messages: slightly elevated dark card, left aligned
- User messages: accent color background, right aligned
- Font: SF Pro (system default, no need to import)
- No gradients, no heavy shadows, no rounded corners on main containers
- Tab bar: dark, minimal icons

Do not use colorful gradients or anything that looks like a consumer social app. This is a technical portfolio project, it should look like one.

## Tech Notes

- URLSession for REST calls (no third party HTTP library needed)
- URLSessionWebSocketTask for WebSocket (built into URLSession, no third party library)
- LocalAuthentication for FaceID
- Security framework for Keychain
- Swift concurrency (async/await) throughout, no completion handlers
- @MainActor for all UI updates
- No third party dependencies. Zero. This is intentional for a portfolio project.
- Minimum deployment target: iOS 17
- Swift 5.9+

## FaceID Flow

FaceID protects access to the stored JWT, it is not a network auth mechanism. The server never knows about FaceID.

1. First login: user enters password, server returns tokens, store both in Keychain
2. Next app open: trigger FaceID, if success read access token from Keychain and proceed
3. If access token expired: trigger FaceID, read refresh token, hit /auth/refresh, store new access token
4. If refresh token also expired: show LoginView again, require password

## Keychain Keys

- com.lethanial.nova.accessToken
- com.lethanial.nova.refreshToken

## Constants

Base URL: https://miles.lethanial.com
WebSocket URL: wss://miles.lethanial.com/ws

## Coding Preferences

No hyphens in any written output, ever. Swift style: clarity over cleverness. No force unwraps except where truly impossible to fail (and comment why). Comments explain WHY not WHAT. No third party packages. Error states should always be visible to the user, never silently swallowed. Every network call needs a loading state and an error state, not just a success state.

## Critical Learning Constraint

I am a CpE student building this to learn Swift and iOS development for the first time. This is my first Swift project. When making code changes:

1. Explain what we are about to do before writing code. Explain Swift concepts I may not know.
2. Make small, logical changes one at a time. Do not scaffold the entire app in one shot.
3. Pause after meaningful changes and ask if I have questions.
4. Quiz me on important Swift concepts (optionals, property wrappers, async/await, SwiftUI state management) so misunderstandings get caught early.
5. When you introduce a new Swift concept (@StateObject, @ObservableObject, @EnvironmentObject, actors, etc.), explain what it does and why we chose it over alternatives before using it.
6. Do not use third party packages to skip learning. If something can be done with native Apple frameworks, do it natively.
7. Do not use hyphens in anything you write for me.
8. If I push back on your approach, defend your position if you believe it is right. Do not just fold to please me. I value honesty above everything.

## What NOT to Do

- Do not add audio recording or playback. Text only in v0.7.
- Do not add push notifications yet.
- Do not add a settings screen yet (just hardcode the base URL in Constants.swift for now).
- Do not add iCloud sync.
- Do not install any Swift packages or CocoaPods or SPM dependencies.
- Do not suggest changes to the Pi backend.
- Do not use hyphens anywhere.

## Session Handoff Note

When the app is complete and testable on simulator, remind me to:
1. Add my Apple Developer account in Xcode (Xcode > Settings > Accounts)
2. Set the team in the project signing settings
3. Connect my iPhone via cable
4. Run on physical device to test FaceID (simulator cannot test FaceID with real biometrics)
