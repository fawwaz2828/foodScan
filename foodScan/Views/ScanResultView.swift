//
//  ScanResultView.swift
//  foodScan
//
//  Kartu hasil scan bergaya Cal AI: nama makanan, total kalori, rincian macro
//  (Carbs/Fat/Protein vs target harian), Healthy Score, lalu rekomendasi harian.
//

import SwiftUI

struct ScanResultView: View {
    let result: ScanPipelineResult

    private var record: ScanRecord { result.record }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Nama + total kalori
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Total \(record.calories) kcal", systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.brand)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(Int(record.confidence * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.secondaryText)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.brandSoft, in: Capsule())
                    .fixedSize()
            }

            // Macro + Healthy Score (muncul setelah enrichment gizi)
            if let nutrition = record.nutrition {
                MacroCardsRow(nutrition: nutrition, dailyTarget: result.recommendation.dailyTarget)
                HealthyScoreBar(score: nutrition.healthScore)
                if !nutrition.insight.isEmpty {
                    Text(nutrition.insight)
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryText)
                }
                if let ingredients = nutrition.ingredients, !ingredients.isEmpty {
                    IngredientsCard(ingredients: ingredients)
                }
            }

            Divider().overlay(Color.black.opacity(0.08))

            // Rekomendasi harian (Agent 4)
            let rec = result.recommendation
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusIcon(rec.status))
                    .foregroundStyle(Color.brand)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today: \(rec.totalCaloriesToday) / \(rec.dailyTarget) kcal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(rec.message)
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func statusIcon(_ s: CalorieStatus) -> String {
        switch s {
        case .low: return "arrow.down.circle.fill"
        case .onTrack: return "checkmark.circle.fill"
        case .high: return "exclamationmark.triangle.fill"
        }
    }
}
