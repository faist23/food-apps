//
//  ElevatedCard.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/19/26.
//

import SwiftUI
import BiteLedgerCore

struct ElevatedCard<Content: View>: View {

    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 24
    var content: () -> Content

    init(
        padding: CGFloat = 20,
        cornerRadius: CGFloat = 24,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color("SurfaceCard"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color("DividerSubtle"), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(0.35),
                radius: 16,
                y: 8
            )
    }
}
