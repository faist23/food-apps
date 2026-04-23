import SwiftUI

public struct ElevatedCard<Content: View>: View {

    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 24
    var content: () -> Content

    public init(
        padding: CGFloat = 20,
        cornerRadius: CGFloat = 24,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.dividerSubtle, lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(0.35),
                radius: 16,
                y: 8
            )
    }
}
