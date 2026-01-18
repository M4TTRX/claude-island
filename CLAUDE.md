# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Claude Island is a macOS menu bar app that provides Dynamic Island-style notifications for Claude Code CLI sessions. It monitors sessions in real-time, displays permission approval prompts in the notch overlay, and renders chat history with markdown support.

**Requirements:** macOS 15.6+, Xcode 16.x, Swift 5.9+

## Build Commands

```bash
# Build release app (ad-hoc signed)
./scripts/build.sh

# Build via xcodebuild directly
xcodebuild -scheme ClaudeIsland -configuration Release build

# Run pre-commit linters (SwiftFormat, SwiftLint, Ruff)
prek run --all-files

# Create release DMG (after build)
./scripts/create-release.sh --skip-notarization
```

## Architecture

### Event-Driven State Machine

The app uses a unidirectional data flow pattern where all state mutations flow through a single `SessionStore` actor:

- **`SessionStore`** (`Services/State/SessionStore.swift`): Central actor managing all session state. All mutations go through the `process(_ event: SessionEvent)` method. Uses `CurrentValueSubject` to publish state changes to SwiftUI views.

- **`SessionEvent`** (`Models/SessionEvent.swift`): Typed enum representing all possible state mutations (hook received, permission approved/denied, file updated, etc.)

- **`SessionPhase`** (`Models/SessionPhase.swift`): Enum-based state machine representing UI phases (idle, processing, waitingForApproval, waitingForInput, compacting). Includes `canTransition(to:)` validation.

### Hook Communication System

Claude Island integrates with Claude Code via hooks installed in `~/.claude/hooks/`:

1. **Python Hook Script** (`Resources/claude-island-state.py`): Installed to `~/.claude/hooks/`. Sends session events to the app via Unix socket. For permission requests, waits for user decisions.

2. **HookInstaller** (`Services/Hooks/HookInstaller.swift`): Auto-installs/updates the hook script and configures `~/.claude/settings.json` on app launch.

3. **HookSocketServer** (`Services/Hooks/HookSocketServer.swift`): Unix domain socket server at `/tmp/claude-island.sock`. Receives events from hooks and maintains open connections for permission request/response.

### JSONL Parsing & File Watching

- **ConversationParser** (`Services/Session/ConversationParser.swift`): Parses Claude Code's JSONL conversation files. Supports incremental parsing to avoid re-reading entire files.

- **AgentFileWatcher** / **JSONLInterruptWatcher**: Monitor conversation files for changes to detect interrupts and `/clear` commands.

### UI Layer

- **NotchWindow** / **NotchViewController**: Custom `NSPanel` subclass for the floating notch overlay that appears above other windows.

- **NotchViewModel** (`Core/NotchViewModel.swift`): `@Observable` view model coordinating between `SessionStore` and SwiftUI views.

- **Views**: `NotchView`, `ChatView`, `ClaudeInstancesView` - SwiftUI views for the overlay UI.

### Key Patterns

- Swift actors for thread-safe shared state (`SessionStore`, `ConversationParser`)
- `@Observable` macro for SwiftUI view models (not `ObservableObject`)
- `@MainActor` for UI-related code
- Combine publishers bridged to SwiftUI via `sessionsPublisher`
- Exponential backoff with jitter for socket reconnection

## Coding Guidelines

The project follows modern Swift 5.9-6.x patterns documented in `.augment/rules/swift-dev-pro.md`:

- Use actors for shared mutable state, `@MainActor` for view models
- Prefer `@Observable` with `@State` over `ObservableObject` with `@StateObject`
- Use structured concurrency (`async let`, `TaskGroup`) over fire-and-forget tasks
- Handle actor reentrancy defensively (validate state after `await`)
- Use `AsyncStream` for bridging callback-based APIs to async/await

The Python hook script follows Python 3.14+ patterns in `.augment/rules/python-314-pro.md`:

- Type hints with `TypedDict`, `TypeIs`, `dataclass(slots=True, frozen=True)`
- Pattern matching for event dispatch
- Bracketless `except` for multiple exception types

## Linting Configuration

Pre-commit hooks run:

- **SwiftFormat** (0.55.3): Auto-formats Swift code
- **SwiftLint** (0.57.1): 70+ lint rules in strict mode
- **Ruff**: Lints/formats Python hook script
- **Shellcheck**: Validates shell scripts

## Key Files

| File | Purpose |
|------|---------|
| `Services/State/SessionStore.swift` | Central state actor - start here to understand state flow |
| `Services/Hooks/HookSocketServer.swift` | Socket server for hook communication |
| `Resources/claude-island-state.py` | Python hook script sent to Claude Code |
| `Core/NotchViewModel.swift` | Main UI view model |
| `Models/SessionPhase.swift` | Phase state machine with transition validation |
