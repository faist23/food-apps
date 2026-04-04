//
//  RecipeCardView.swift
//  BitePlan
//
//  Reusable grid card used by RecipesListView and RecipeSearchView.
//  Shows a full-bleed 150pt photo (or BrandPrimary gradient placeholder),
//  the recipe name, and optional cook time.
//

import SwiftUI
import BiteLedgerCore

struct RecipeCardView: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo area: Rectangle anchors layout — AsyncImage overlaid so it
            // can never inflate the card's width/height.
            Rectangle()
                .fill(Color("SurfaceCard"))
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .overlay(
                    RecipePhotoView(urlString: recipe.imageURL, contentMode: .fill) {
                        recipeCardPlaceholder
                    }
                )
                .clipped()

            // Name + time metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("TextPrimary"))
                    .lineLimit(2)

                if let minutes = recipe.totalMinutes ?? recipe.cookMinutes, minutes > 0 {
                    Label(formatMinutes(minutes), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(Color("TextSecondary"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(Color("SurfaceCard"), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color("DividerSubtle"), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var recipeCardPlaceholder: some View {
        // BrandPrimary gradient + utensils icon — intentional, not broken-looking.
        ZStack {
            LinearGradient(
                colors: [Color("BrandPrimary").opacity(0.7), Color("BrandPrimary")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "fork.knife")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func formatMinutes(_ m: Int) -> String {
        if m < 60 { return "\(m) min" }
        let h = m / 60; let r = m % 60
        return r == 0 ? "\(h) hr" : "\(h) hr \(r) min"
    }
}
