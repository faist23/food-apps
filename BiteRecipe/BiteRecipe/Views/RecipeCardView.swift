//
//  RecipeCardView.swift
//  BiteRecipe
//
//  Reusable grid card used by RecipesListView and RecipeSearchView.
//  Shows a full-bleed 150pt photo (or BrandPrimary gradient placeholder),
//  the recipe name, and optional cook time.
//

import SwiftUI
import BiteLedgerCore

struct RecipeCardView: View {
    let recipe: Recipe
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cookMinutes: Int? {
        if let m = recipe.totalMinutes ?? recipe.cookMinutes, m > 0 { return m }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo area: Rectangle anchors layout — AsyncImage overlaid so it
            // can never inflate the card's width/height.
            Rectangle()
                .fill(Color.surfaceCard)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .overlay(
                    RecipePhotoView(urlString: recipe.imageURL, contentMode: .fill) {
                        recipeCardPlaceholder
                    }
                )
                .overlay(alignment: .bottomTrailing) {
                    if let minutes = cookMinutes {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                            Text(formatMinutes(minutes))
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(6)
                    }
                }
                .clipped()
                .accessibilityHidden(true)

            // Name + time metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                if let minutes = cookMinutes {
                    Label(formatMinutes(minutes), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.dividerSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(recipe.name)\(cookMinutes.map { ", \(formatMinutes($0)) cook time" } ?? "")")
        .accessibilityHint("Double tap to open")
    }

    @ViewBuilder
    private var recipeCardPlaceholder: some View {
        if reduceMotion {
            ZStack {
                LinearGradient(
                    colors: [Color.brandPrimary.opacity(0.7), Color.brandPrimary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "fork.knife")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.8))
            }
        } else {
            TimelineView(.animation) { context in
                let phase = (context.date.timeIntervalSinceReferenceDate / 1.5)
                    .truncatingRemainder(dividingBy: 1.0)
                ZStack {
                    AngularGradient(
                        colors: [
                            Color.brandPrimary.opacity(0.5),
                            Color.brandPrimary,
                            Color.brandPrimary.opacity(0.5)
                        ],
                        center: .center,
                        startAngle: .degrees(phase * 360),
                        endAngle: .degrees(phase * 360 + 360)
                    )
                    Image(systemName: "fork.knife")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private func formatMinutes(_ m: Int) -> String {
        if m < 60 { return "\(m) min" }
        let h = m / 60; let r = m % 60
        return r == 0 ? "\(h) hr" : "\(h) hr \(r) min"
    }
}
