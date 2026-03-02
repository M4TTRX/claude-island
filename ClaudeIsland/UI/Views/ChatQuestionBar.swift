//
//  ChatQuestionBar.swift
//  ClaudeIsland
//
//  Interactive question answering bar for AskUserQuestion prompts.
//  Supports single-question, multi-question wizard, and multiSelect flows.
//

import SwiftUI

/// Interactive question answering bar shown when AskUserQuestion data is parseable.
/// Handles single-question (immediate submit), multiSelect (checkboxes + submit),
/// and multi-question wizard (breadcrumbs, per-question answers, review step).
struct ChatQuestionBar: View {
    let questions: [QuestionItem]
    let isInTmux: Bool
    let onSelectOption: (_ questionIndex: Int, _ optionIndex: Int) -> Void
    let onSubmitText: (_ questionIndex: Int, _ text: String) -> Void
    /// Called when multi-question wizard completes with all collected answers
    let onSubmitAllAnswers: (_ answers: [(questionIndex: Int, selectedIndices: Set<Int>, isMultiSelect: Bool)]) -> Void
    /// Called when wizard is cancelled (deny permission)
    let onCancel: () -> Void
    let onGoToTerminal: () -> Void

    // MARK: - State

    /// Maps question index -> set of selected option indices
    @State private var collectedAnswers: [Int: Set<Int>] = [:]
    /// 0..<questions.count for questions, questions.count for review step
    @State private var currentStep: Int = 0
    @State private var freeTextInput: String = ""
    @State private var showFreeText: Bool = false
    @State private var showContent = false
    @State private var showOptions = false
    @FocusState private var isTextFieldFocused: Bool

    private var isMultiQuestion: Bool { questions.count > 1 }
    private var isReviewStep: Bool { currentStep == questions.count }
    private var totalSteps: Int { questions.count + (isMultiQuestion ? 1 : 0) } // +1 for review

    private var currentQuestion: QuestionItem? {
        guard currentStep < questions.count else { return nil }
        return questions[currentStep]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Breadcrumbs (multi-question only)
            if isMultiQuestion {
                breadcrumbBar
            }

            if isReviewStep {
                reviewStep
            } else if let question = currentQuestion {
                questionContent(question)
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

    // MARK: - Breadcrumb Bar

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    breadcrumbPill(
                        label: question.header ?? "Q\(index + 1)",
                        stepIndex: index,
                        isCompleted: collectedAnswers[index] != nil,
                        isCurrent: currentStep == index
                    )

                    if index < questions.count - 1 || true {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white.opacity(0.25))
                    }
                }

                // Submit breadcrumb
                breadcrumbPill(
                    label: "Submit",
                    stepIndex: questions.count,
                    isCompleted: false,
                    isCurrent: isReviewStep
                )
            }
            .padding(.vertical, 2)
        }
        .opacity(showContent ? 1 : 0)
    }

    private func breadcrumbPill(label: String, stepIndex: Int, isCompleted: Bool, isCurrent: Bool) -> some View {
        Button {
            // Allow navigating back to completed steps or current step
            if isCompleted || stepIndex <= currentStep {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    currentStep = stepIndex
                    showFreeText = false
                    resetAnimations()
                }
            }
        } label: {
            HStack(spacing: 3) {
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(label)
                    .font(.system(size: 10, weight: isCurrent ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(
                isCurrent ? .white.opacity(0.9) :
                isCompleted ? TerminalColors.green.opacity(0.8) :
                .white.opacity(0.35)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrent ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isCompleted && stepIndex > currentStep)
    }

    // MARK: - Question Content

    private func questionContent(_ question: QuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            questionHeader(question)

            if !isInTmux {
                tmuxRequiredHint
            }

            if !question.options.isEmpty && !showFreeText {
                if question.multiSelect {
                    checkboxOptions(question.options)
                } else {
                    optionButtons(question.options)
                }
            }

            if showFreeText {
                freeTextInputBar
            }

            bottomControls(question: question)
        }
    }

    // MARK: - Tmux Required Hint

    private var tmuxRequiredHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(TerminalColors.amber)
            Text("Run Claude Code in tmux to answer here")
                .font(.system(size: 11))
                .foregroundColor(TerminalColors.amber.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TerminalColors.amber.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(TerminalColors.amber.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Question Header

    private func questionHeader(_ question: QuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !isMultiQuestion {
                Text(MCPToolFormatter.formatToolName("AskUserQuestion"))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(TerminalColors.amber)
            }

            Text(question.question)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if !isMultiQuestion && questions.count == 1 && question.multiSelect {
                Text("Select one or more options")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .opacity(showContent ? 1 : 0)
        .offset(x: showContent ? 0 : -10)
    }

    // MARK: - Single-Select Option Buttons

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
                    if isMultiQuestion {
                        // Store answer and advance
                        collectedAnswers[currentStep] = [index]
                        advanceStep()
                    } else {
                        // Single question, single-select: immediate submit
                        onSelectOption(currentStep, index)
                    }
                }
            }
        }
        .opacity(showOptions ? 1 : 0)
        .scaleEffect(showOptions ? 1 : 0.95)
    }

    // MARK: - MultiSelect Checkbox Options

    private func checkboxOptions(_ options: [QuestionOption]) -> some View {
        let selected = collectedAnswers[currentStep] ?? []
        let columns = options.count <= 4
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

        return VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    CheckboxOptionButton(
                        label: option.label,
                        description: option.description,
                        isSelected: selected.contains(index),
                        isEnabled: isInTmux
                    ) {
                        toggleSelection(index)
                    }
                }
            }

            // Next/Submit button for multiSelect
            HStack {
                Spacer()
                Button {
                    if isMultiQuestion {
                        advanceStep()
                    } else {
                        // Single question, multiSelect: submit immediately
                        let selected = collectedAnswers[0] ?? []
                        onSubmitAllAnswers([(
                            questionIndex: 0,
                            selectedIndices: selected,
                            isMultiSelect: true
                        )])
                    }
                } label: {
                    Text(isMultiQuestion ? "Next" : "Submit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    (collectedAnswers[currentStep]?.isEmpty ?? true)
                                    ? Color.white.opacity(0.3)
                                    : Color.white.opacity(0.95)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(collectedAnswers[currentStep]?.isEmpty ?? true)
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

            if isMultiQuestion {
                Button {
                    onCancel()
                } label: {
                    HStack(spacing: 3) {
                        Text("Cancel")
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

    // MARK: - Review Step

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review your answers")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            // Summary of each answer
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                VStack(alignment: .leading, spacing: 2) {
                    Text(question.header ?? question.question)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)

                    if let selected = collectedAnswers[index] {
                        let labels = selected.sorted().compactMap { idx -> String? in
                            guard idx < question.options.count else { return nil }
                            return question.options[idx].label
                        }
                        Text(labels.joined(separator: ", "))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    } else {
                        Text("No answer")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                            .italic()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                )
                .onTapGesture {
                    // Navigate back to that question
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        currentStep = index
                        showFreeText = false
                        resetAnimations()
                    }
                }
            }

            // Submit / Cancel buttons
            HStack(spacing: 10) {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    submitAllAnswers()
                } label: {
                    Text("Submit")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.95))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .opacity(showContent ? 1 : 0)
    }

    // MARK: - Actions

    private func toggleSelection(_ optionIndex: Int) {
        var selected = collectedAnswers[currentStep] ?? []
        if selected.contains(optionIndex) {
            selected.remove(optionIndex)
        } else {
            selected.insert(optionIndex)
        }
        collectedAnswers[currentStep] = selected
    }

    private func advanceStep() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            currentStep += 1
            showFreeText = false
            resetAnimations()
        }
    }

    private func resetAnimations() {
        showContent = false
        showOptions = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showContent = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                showOptions = true
            }
        }
    }

    private func submitFreeText() {
        let text = freeTextInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        freeTextInput = ""
        onSubmitText(currentStep, text)
    }

    private func submitAllAnswers() {
        let answers: [(questionIndex: Int, selectedIndices: Set<Int>, isMultiSelect: Bool)] =
            questions.enumerated().compactMap { index, question in
                guard let selected = collectedAnswers[index], !selected.isEmpty else { return nil }
                return (questionIndex: index, selectedIndices: selected, isMultiSelect: question.multiSelect)
            }
        onSubmitAllAnswers(answers)
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

// MARK: - Checkbox Option Button

struct CheckboxOptionButton: View {
    let label: String
    let description: String?
    let isSelected: Bool
    let isEnabled: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            if isEnabled { onToggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(
                        isSelected
                        ? TerminalColors.green
                        : (isEnabled ? .white.opacity(0.4) : .white.opacity(0.2))
                    )

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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isSelected ? Color.white.opacity(0.08) :
                        (isHovered && isEnabled ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isSelected ? TerminalColors.green.opacity(0.4) : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
