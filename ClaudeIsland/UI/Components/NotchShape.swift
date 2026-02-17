//
//  NotchShape.swift
//  ClaudeIsland
//
//  Accurate notch shape using quadratic curves
//

import SwiftUI

struct NotchShape: Shape {
    // MARK: Lifecycle

    init(
        topCornerRadius: CGFloat = 6,
        bottomCornerRadius: CGFloat = 14,
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    // MARK: Internal

    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            .init(self.topCornerRadius, self.bottomCornerRadius)
        }
        set {
            self.topCornerRadius = newValue.first
            self.bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        self.addTopLeftCorner(to: &path, rect: rect)
        self.addLeftEdge(to: &path, rect: rect)
        self.addBottomLeftCorner(to: &path, rect: rect)
        self.addBottomEdge(to: &path, rect: rect)
        self.addBottomRightCorner(to: &path, rect: rect)
        self.addRightEdge(to: &path, rect: rect)
        self.addTopRightCorner(to: &path, rect: rect)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }

    // MARK: Private

    private func addTopLeftCorner(to path: inout Path, rect: CGRect) {
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + self.topCornerRadius, y: rect.minY + self.topCornerRadius),
            control: CGPoint(x: rect.minX + self.topCornerRadius, y: rect.minY),
        )
    }

    private func addLeftEdge(to path: inout Path, rect: CGRect) {
        path.addLine(to: CGPoint(x: rect.minX + self.topCornerRadius, y: rect.maxY - self.bottomCornerRadius))
    }

    private func addBottomLeftCorner(to path: inout Path, rect: CGRect) {
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + self.topCornerRadius + self.bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + self.topCornerRadius, y: rect.maxY),
        )
    }

    private func addBottomEdge(to path: inout Path, rect: CGRect) {
        path.addLine(to: CGPoint(x: rect.maxX - self.topCornerRadius - self.bottomCornerRadius, y: rect.maxY))
    }

    private func addBottomRightCorner(to path: inout Path, rect: CGRect) {
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - self.topCornerRadius, y: rect.maxY - self.bottomCornerRadius),
            control: CGPoint(x: rect.maxX - self.topCornerRadius, y: rect.maxY),
        )
    }

    private func addRightEdge(to path: inout Path, rect: CGRect) {
        path.addLine(to: CGPoint(x: rect.maxX - self.topCornerRadius, y: rect.minY + self.topCornerRadius))
    }

    private func addTopRightCorner(to path: inout Path, rect: CGRect) {
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - self.topCornerRadius, y: rect.minY),
        )
    }
}

/// Pill shape for external displays without a notch.
/// Unlike NotchShape, this has uniform rounded corners on all sides
/// (no inward-curving top corners that mimic a physical notch).
struct PillShape: Shape {
    var cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
    }

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        return Path(roundedRect: rect, cornerRadius: r)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Notch: Closed state
        NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
            .fill(.black)
            .frame(width: 200, height: 32)

        // Notch: Open state
        NotchShape(topCornerRadius: 19, bottomCornerRadius: 24)
            .fill(.black)
            .frame(width: 600, height: 200)

        // Pill: Closed state (menu bar height)
        PillShape(cornerRadius: 12)
            .fill(.black)
            .frame(width: 180, height: 24)

        // Pill: Open state
        PillShape(cornerRadius: 20)
            .fill(.black)
            .frame(width: 480, height: 320)
    }
    .padding(20)
    .background(Color.gray.opacity(0.3))
}
