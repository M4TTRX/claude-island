//
//  ChatQuestionBar.swift
//  ClaudeIsland
//
//  Interactive question answering bar for AskUserQuestion prompts
//

import SwiftUI

/// Interactive question answering bar shown when AskUserQuestion data is parseable
struct ChatQuestionBar: View {
    let questions: [QuestionItem]
    let isInTmux: Bool
    let onSelectOption: (_ questionIndex: Int, _ optionIndex: Int) -> Void
    let onSubmitText: (_ questionIndex: Int, _ text: String) -> Void
    let onGoToTerminal: () -> Void

    @State private var currentQuestionIndex: Int = 0
    @State private var freeTextInput: String = ""
    @State private var showFreeText: Bool = false
    @State private var showContent = false
    @State private var showOptions = false
    @FocusState private var isTextFieldFocused: Bool

    private var currentQuestion: QuestionItem? {
        guard currentQuestionIndex < questions.count else { return nil }
        return questions[currentQuestionIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            questionHeader

            if let question = currentQuestion {
                if !question.options.isEmpty && !showFreeText {
                    optionButtons(question.options)
                }

                if showFreeText {
                    freeTextInputBar
                }

                bottomControls(question: question)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showContent = true
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.1)) {
                showOptions = true
            }
        }
    }

    // MARK: - Question Header

    private var questionHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(MCPToolFormatter.formatToolName("AskUserQuestion"))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(TerminalColors.amber)

            if let question = currentQuestion {
                Text(question.question)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                if questions.count > 1 {
                    Text("Question \(currentQuestionIndex + 1) of \(questions.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .opacity(showContent ? 1 : 0)
        .offset(x: showContent ? 0 : -10)
    }

    // MARK: - Option Buttons

    private func optionButtons(_ options: [QuestionOption]) -> some View {
        let columns = options.count <= 4
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                OptionButton(
                    label: option.label,
                    description: option.description,
                    isEnabled: isInTmux
                ) {
                    onSelectOption(currentQuestionIndex, index)
                }
            }
        }
        .opacity(showOptions ? 1 : 0)
        .scaleEffect(showOptions ? 1 : 0.95)
    }

    // MARK: - Free Text Input

    private var freeTextInputBar: some View {
        HStack(spacing: 8) {
            TextField("Type your answer...", text: $freeTextInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .focused($isTextFieldFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .onSubmit {
                    submitFreeText()
                }

            Button {
                submitFreeText()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(freeTextInput.isEmpty ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(freeTextInput.isEmpty)
        }
        .opacity(showOptions ? 1 : 0)
        .onAppear {
            isTextFieldFocused = true
        }
    }

    // MARK: - Bottom Controls

    private func bottomControls(question: QuestionItem) -> some View {
        HStack(spacing: 8) {
            if !question.options.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        showFreeText.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showFreeText ? "list.bullet" : "keyboard")
                            .font(.system(size: 10, weight: .medium))
                        Text(showFreeText ? "Show options" : "Type something")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                onGoToTerminal()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9, weight: .medium))
                    Text("Terminal")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .opacity(showOptions ? 1 : 0)
    }

    // MARK: - Actions

    private func submitFreeText() {
        let text = freeTextInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        freeTextInput = ""
        onSubmitText(currentQuestionIndex, text)
    }
}

// MARK: - Option Button

struct OptionButton: View {
    let label: String
    let description: String?
    let isEnabled: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            if isEnabled { onTap() }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isEnabled ? .white.opacity(0.9) : .white.opacity(0.4))
                    .lineLimit(1)

                if let desc = description {
                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered && isEnabled ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
