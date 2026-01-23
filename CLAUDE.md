# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Claude Island is a macOS menu bar app that provides Dynamic Island-style notifications for Claude Code CLI sessions. It monitors Claude sessions via Unix domain sockets, displays real-time status in an animated notch overlay, and enables permission approvals without switching to the terminal.

**Requirements:** macOS 15.6+, Xcode 16.x, Swift 5.9+, [uv](https://docs.astral.sh/uv/) (Python package manager)

## Build Commands

```bash
# Build release app (ad-hoc signed, outputs to build/export/)
./scripts/build.sh

# Build with Xcode directly
xcodebuild -scheme ClaudeIsland -configuration Release build

# Run pre-commit linters (SwiftFormat, SwiftLint, Ruff, Shellcheck, Markdownlint)
prek run --all-files

# Run specific linter
swiftlint lint --strict ClaudeIsland/
swiftformat --lint ClaudeIsland/
```

## Architecture

### State Management Pattern

All session state flows through `SessionStore` (actor-based singleton at `Services/State/SessionStore.swift`):

- Single source of truth for all Claude sessions
- Event-driven state machine: all mutations via `process(_ event:)` method
- Publishes changes via Combine `sessionsPublisher`
- 11+ event types: `hookReceived`, `permissionApproved`, `fileUpdated`, etc.

### Concurrency Model (Swift 6)

The codebase uses **Swift 6 language mode with strict concurrency**:

- `@MainActor` for UI classes: `AppDelegate`, `NotchViewModel`, all views
- `actor` for background state: `SessionStore`, `SocketReconnectionManager`
- `Sendable` conformance on all shared data: `SessionState`, `HookEvent`, models
- Structured concurrency with async/await throughout

### Key Services

| Service | Location | Purpose |
|---------|----------|---------|
| `HookSocketServer` | `Services/Hooks/` | Unix socket server at `~/.claude/hooks/socket` for real-time hook events |
| `ClaudeSessionMonitor` | `Services/Session/` | Orchestrates session monitoring, file watching, JSONL parsing |
| `SessionStore` | `Services/State/` | Central state actor, processes all events |
| `NotchViewModel` | `UI/` | UI state: notch status, content types, geometry |
| `TmuxSessionMatcher` | `Services/Tmux/` | Matches sessions to tmux targets for terminal focusing |

### UI Architecture

- `@Observable` macro (not `ObservableObject`) for property-level observation
- `NotchWindow` / `NotchWindowController` for custom notch-shaped window
- `NotchView` as main animated overlay that expands from MacBook notch
- Reusable components in `UI/Components/`: `ActionButton`, `MarkdownRenderer`, `StatusIcons`

### Data Flow

```
Hook Script → Unix Socket → HookSocketServer → SessionStore.process() → NotchViewModel → SwiftUI Views
                                                       ↓
JSONL Files → ConversationParser → SessionStore.process()
```

### Key Models

- `SessionState`: Core session data with state machine (`phase`: idle → processing → waiting → complete)
- `HookEvent`: Socket messages with sessionID, cwd, event, status, tool info
- `ChatMessage`: Parsed messages with blocks (text, toolUse, thinking)
- `ToolTracker`: Unified tool execution tracking

## Swift Patterns

Per `.augment/rules/swift-dev-pro.md`:

- **Value types by default**: Use structs unless reference semantics needed
- **Explicit access control**: Start `private`, open as needed
- **Actor selection**: Only when protecting non-Sendable mutable state shared across contexts
- **`some` vs `any`**: Use `some` for returns (better performance), `any` for heterogeneous collections

## Linting Configuration

- **SwiftLint** (`.swiftlint.yml`): 70+ opt-in rules, strict mode
- **SwiftFormat** (`.swiftformat`): Swift 5.9, 150 char lines, 4-space indent
- **Ruff**: Python 3.14+ for hook scripts in `ClaudeIsland/Resources/`

## Dependencies (Swift Package Manager)

- `swift-markdown` - Markdown rendering
- `Sparkle` - Auto-updates via appcast.xml
- `OcclusionKit` - Notch occlusion detection
- `Subprocess` - Process execution
