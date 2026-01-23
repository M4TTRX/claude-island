# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Claude Island is a macOS menu bar app that displays Claude Code CLI session status in a Dynamic Island-style notch interface. It monitors running Claude Code instances, shows their status (idle, processing, waiting for approval), and enables tool approval/denial directly from the notch UI.

**Requirements:** macOS 15.6+, Xcode 16.x, Swift 6 language mode

## Build Commands

```bash
# Build release app (ad-hoc signed)
./scripts/build.sh

# Build via xcodebuild directly
xcodebuild -scheme ClaudeIsland -configuration Release build

# Create DMG for distribution (after build.sh)
./scripts/create-release.sh --skip-notarization

# Run linters (requires prek installed via brew)
prek run --all-files

# Run specific linters
swiftformat .
swiftlint lint --strict
ruff check ClaudeIsland/Resources/*.py --fix
```

## Architecture

### Data Flow

```
Claude Code CLI → Python Hook → Unix Socket → HookSocketServer → SessionStore → NotchViewModel → NotchView
```

1. **Python Hook** (`ClaudeIsland/Resources/claude-island-state.py`): Installed to `~/.claude/hooks/`, receives events from Claude Code hooks system, sends JSON to Unix socket at `/tmp/claude-island.sock`

2. **HookSocketServer** (`Services/Hooks/HookSocketServer.swift`): Listens on Unix socket, decodes hook events, dispatches to SessionStore

3. **SessionStore** (`Services/State/SessionStore.swift`): Central actor managing all session state. All mutations flow through `process(_ event:)` method. Publishes state changes via Combine publisher for UI updates

4. **NotchViewModel** (`Core/NotchViewModel.swift`): @Observable view model managing notch UI state (open/closed/popping), content type, and mouse event handling

5. **UI Views** (`UI/Views/`): SwiftUI views for notch display, session list, chat history, and settings menu

### Key Abstractions

- **SessionPhase**: Enum representing session lifecycle (`.idle`, `.processing`, `.waitingForApproval`, `.waitingForInput`)
- **SessionEvent**: Events that trigger state transitions (hook received, permission approved/denied, file updated, etc.)
- **ChatHistoryItem**: Unified type for conversation display (text, tool calls, thinking blocks)

### Hook System

The app auto-installs hooks on launch via `HookInstaller`. Hooks are registered for: `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Notification`, `Stop`, `SubagentStop`, `SessionStart`, `SessionEnd`, `PreCompact`.

For permission requests, the Python hook waits synchronously (up to 5 minutes) for a response from the app, then outputs the decision to stdout for Claude Code to process.

### JSONL Parsing

`ConversationParser` (`Services/Session/ConversationParser.swift`) reads Claude Code's JSONL files from `~/.claude/projects/*/sessions/*.jsonl` to:

- Extract conversation history for chat display
- Detect tool completions and results
- Track subagent (Task tool) activity

### Window Management

The notch window is a custom NSWindow positioned over the macOS notch (or centered top on non-notch displays). Uses `OcclusionKit` to detect when the notch area is obscured by other windows.

## Key Dependencies

- **Sparkle**: Auto-updates
- **swift-markdown**: Markdown rendering in chat
- **OcclusionKit**: Window occlusion detection
- **swift-subprocess**: Process execution

## Coding Patterns

This codebase follows Swift 6 strict concurrency. Key patterns:

- **Actors for shared state**: `SessionStore` is an actor; all state access is isolated
- **@MainActor for UI**: ViewModels and UI-related code use `@MainActor`
- **@Observable for SwiftUI**: Use `@Observable` macro instead of `ObservableObject`
- **Event-driven state machine**: SessionStore processes events rather than exposing direct mutation methods

See `.augment/rules/swift-dev-pro.md` for comprehensive Swift 6 guidelines.
