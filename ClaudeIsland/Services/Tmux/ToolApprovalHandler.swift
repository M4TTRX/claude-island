//
//  ToolApprovalHandler.swift
//  ClaudeIsland
//
//  Handles Claude tool approval operations via tmux
//

import Foundation
import os.log

/// Handles tool approval and rejection for Claude instances
actor ToolApprovalHandler {
    static let shared = ToolApprovalHandler()

    /// Logger for tool approval (nonisolated static for cross-context access)
    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "Approval")

    private init() {}

    /// Approve a tool once (sends '1' + Enter)
    func approveOnce(target: TmuxTarget) async -> Bool {
        await sendKeys(to: target, keys: "1", pressEnter: true)
    }

    /// Approve a tool always (sends '2' + Enter)
    func approveAlways(target: TmuxTarget) async -> Bool {
        await sendKeys(to: target, keys: "2", pressEnter: true)
    }

    /// Reject a tool with optional message
    func reject(target: TmuxTarget, message: String? = nil) async -> Bool {
        // First send 'n' + Enter to reject
        guard await sendKeys(to: target, keys: "n", pressEnter: true) else {
            return false
        }

        // If there's a message, send it after a brief delay
        if let message = message, !message.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
            return await sendKeys(to: target, keys: message, pressEnter: true)
        }

        return true
    }

    /// Send a message to a tmux target
    func sendMessage(_ message: String, to target: TmuxTarget) async -> Bool {
        await sendKeys(to: target, keys: message, pressEnter: true)
    }

    /// Select an option from an interactive CLI selector by sending Down-arrow keys + Enter.
    /// The selector starts with cursor on option 0. To select option N (0-indexed),
    /// send N Down-arrow keys then Enter.
    func selectOption(at index: Int, to target: TmuxTarget) async -> Bool {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return false
        }

        let targetStr = target.targetString

        do {
            for _ in 0..<index {
                let downArgs = ["send-keys", "-t", targetStr, "Down"]
                _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: downArgs)
                try? await Task.sleep(for: .milliseconds(50))
            }

            let enterArgs = ["send-keys", "-t", targetStr, "Enter"]
            _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: enterArgs)

            return true
        } catch {
            Self.logger.error("selectOption error: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Send a free-text answer by first selecting the "Type something" option,
    /// then typing the text and pressing Enter.
    func sendFreeTextAnswer(_ text: String, typeOptionIndex: Int, to target: TmuxTarget) async -> Bool {
        guard await selectOption(at: typeOptionIndex, to: target) else {
            return false
        }
        try? await Task.sleep(for: .milliseconds(200))
        return await sendMessage(text, to: target)
    }

    /// Select answers for multiple questions in a wizard flow, then submit.
    /// Each answer navigates via Down arrows + Enter/Space depending on single/multi select.
    func selectMultipleAnswers(
        answers: [(questionIndex: Int, selectedIndices: Set<Int>, isMultiSelect: Bool)],
        to target: TmuxTarget
    ) async -> Bool {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return false
        }

        let targetStr = target.targetString

        do {
            for answer in answers {
                if answer.isMultiSelect {
                    // MultiSelect: navigate to each selected option and press Space, then Enter to confirm
                    let sortedIndices = answer.selectedIndices.sorted()
                    var currentPosition = 0
                    for optionIndex in sortedIndices {
                        // Move down to the target option
                        let moves = optionIndex - currentPosition
                        for _ in 0..<moves {
                            let downArgs = ["send-keys", "-t", targetStr, "Down"]
                            _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: downArgs)
                            try? await Task.sleep(for: .milliseconds(50))
                        }
                        // Press Space to toggle selection
                        let spaceArgs = ["send-keys", "-t", targetStr, "Space"]
                        _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: spaceArgs)
                        try? await Task.sleep(for: .milliseconds(50))
                        currentPosition = optionIndex
                    }
                    // Press Enter to confirm selections
                    let enterArgs = ["send-keys", "-t", targetStr, "Enter"]
                    _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: enterArgs)
                } else {
                    // Single-select: navigate to the selected option and press Enter
                    let optionIndex = answer.selectedIndices.first ?? 0
                    for _ in 0..<optionIndex {
                        let downArgs = ["send-keys", "-t", targetStr, "Down"]
                        _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: downArgs)
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    let enterArgs = ["send-keys", "-t", targetStr, "Enter"]
                    _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: enterArgs)
                }

                // Delay between questions for CLI to process
                try? await Task.sleep(for: .milliseconds(200))
            }

            // Final Enter to submit on the review screen (select first option = Submit)
            if answers.count > 1 {
                try? await Task.sleep(for: .milliseconds(200))
                let enterArgs = ["send-keys", "-t", targetStr, "Enter"]
                _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: enterArgs)
            }

            return true
        } catch {
            Self.logger.error("selectMultipleAnswers error: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Private Methods

    private func sendKeys(to target: TmuxTarget, keys: String, pressEnter: Bool) async -> Bool {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return false
        }

        // tmux send-keys needs literal text and Enter as separate arguments
        // Use -l flag to send keys literally (prevents interpreting special chars)
        let targetStr = target.targetString
        let textArgs = ["send-keys", "-t", targetStr, "-l", keys]

        do {
            Self.logger.debug("Sending text to \(targetStr, privacy: .public)")
            _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: textArgs)

            // Send Enter as a separate command if needed
            if pressEnter {
                Self.logger.debug("Sending Enter key")
                let enterArgs = ["send-keys", "-t", targetStr, "Enter"]
                _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: enterArgs)
            }
            return true
        } catch {
            Self.logger.error("Error: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
