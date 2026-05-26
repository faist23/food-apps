//
//  AppToast.swift
//  BiteRecipe
//
//  Unified toast feedback component. Replaces all ad-hoc overlay patterns.
//  Variants: .info, .success, .error, .undo (with action button).
//  Auto-dismisses after 4s. .undo stays until tapped or dismissed.
//

import SwiftUI

// MARK: - Model

struct AppToastModel {
    enum Variant { case info, success, error, undo }
    let id: UUID
    let message: String
    let variant: Variant
    let undoAction: (() -> Void)?

    static func info(_ message: String) -> Self {
        .init(id: UUID(), message: message, variant: .info, undoAction: nil)
    }

    static func success(_ message: String) -> Self {
        .init(id: UUID(), message: message, variant: .success, undoAction: nil)
    }

    static func error(_ message: String) -> Self {
        .init(id: UUID(), message: message, variant: .error, undoAction: nil)
    }

    static func undo(_ message: String, action: @escaping () -> Void) -> Self {
        .init(id: UUID(), message: message, variant: .undo, undoAction: action)
    }
}

// MARK: - View

struct AppToastView: View {
    let model: AppToastModel

    private var iconName: String {
        switch model.variant {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error:   return "xmark.circle.fill"
        case .undo:    return "arrow.uturn.backward.circle.fill"
        }
    }

    private var iconColor: Color {
        switch model.variant {
        case .info, .undo: return .white.opacity(0.8)
        case .success:     return .green
        case .error:       return Color(red: 1, green: 0.4, blue: 0.4)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)

            Text(model.message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if model.variant == .undo, let action = model.undoAction {
                Button("Undo", action: action)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch model.variant {
        case .undo:    return "\(model.message). Undo button available."
        case .error:   return "Error: \(model.message)"
        case .success: return "Success: \(model.message)"
        case .info:    return model.message
        }
    }
}

// MARK: - View Modifier

private struct AppToastModifier: ViewModifier {
    @Binding var toast: AppToastModel?
    @State private var dismissTask: Task<Void, Never>? = nil

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let model = toast {
                AppToastView(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
                    .onTapGesture {
                        if model.variant == .undo { /* undo button handles it */ }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: toast?.id)
        .onChange(of: toast?.id) { _, newID in
            guard newID != nil else { return }
            dismissTask?.cancel()
            guard toast?.variant != .undo else { return }
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation { toast = nil }
                }
            }
        }
    }
}

extension View {
    func appToast(_ toast: Binding<AppToastModel?>) -> some View {
        modifier(AppToastModifier(toast: toast))
    }
}
