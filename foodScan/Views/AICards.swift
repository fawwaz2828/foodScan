//
//  AICards.swift
//  foodScan
//
//  Komponen UI untuk fitur Groq (tema terang): kartu gizi, What-If,
//  portion hint, badge kesehatan, dan tombol Voice Correction.
//

import SwiftUI

// MARK: - Target macro harian (turunan dari target kalori)

enum MacroGoals {
    static func carbs(_ target: Int) -> Double { Double(target) * 0.50 / 4 }   // 50% kkal
    static func fat(_ target: Int) -> Double { Double(target) * 0.25 / 9 }     // 25% kkal
    static func protein(_ target: Int) -> Double { Double(target) * 0.25 / 4 } // 25% kkal
}

// MARK: - Baris kartu macro (Cal AI: Carbs / Fat / Protein vs target harian)

struct MacroCardsRow: View {
    let nutrition: NutritionalInfo
    let dailyTarget: Int

    var body: some View {
        HStack(spacing: 10) {
            MacroCard(title: "Carbs", grams: nutrition.carbsGram,
                      goal: MacroGoals.carbs(dailyTarget), color: .macroCarbs)
            MacroCard(title: "Fat", grams: nutrition.fatGram,
                      goal: MacroGoals.fat(dailyTarget), color: .macroFat)
            MacroCard(title: "Protein", grams: nutrition.proteinGram,
                      goal: MacroGoals.protein(dailyTarget), color: .macroProtein)
        }
    }
}

struct MacroCard: View {
    let title: String
    let grams: Double
    let goal: Double
    let color: Color

    private var ratio: CGFloat { goal > 0 ? min(CGFloat(grams / goal), 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(format: "%.1f", grams))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.primaryText)
                Text("/\(Int(goal))g")
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.18)).frame(height: 5)
                    Capsule().fill(color).frame(width: geo.size.width * ratio, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Ring macro harian (Home dashboard)

struct MacroRing: View {
    let label: String
    let value: Int
    let target: Int
    let color: Color

    private var ratio: CGFloat { target > 0 ? min(CGFloat(value) / CGFloat(target), 1) : 0 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(value)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.primaryText)
            }
            .frame(width: 58, height: 58)
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(Color.primaryText)
            Text("of \(target)g").font(.caption2).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Healthy Score (bar gradien dengan knob)

struct HealthyScoreBar: View {
    let score: Double // 1.0 – 10.0

    private var ratio: CGFloat { CGFloat(min(max(score / 10, 0), 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Healthy Score")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primaryText)
                Spacer()
                Text(String(format: "%.1f/10", score))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brand)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [.red, .orange, .yellow, .green],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.brand, lineWidth: 3))
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .offset(x: max(0, geo.size.width * ratio - 8))
                }
            }
            .frame(height: 16)
        }
    }
}

// MARK: - Kartu Bahan/Komponen (hasil deteksi VLM ChatGPT)

/// Menampilkan setiap bahan/komponen makanan beserta perkiraan berat & kalori.
/// Dirancang sebagai SECTION inline (tanpa kartu sendiri) agar pas dipakai di
/// dalam kartu hasil scan maupun di layar detail.
struct IngredientsCard: View {
    let ingredients: [FoodIngredient]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Detected Ingredients", systemImage: "list.bullet.rectangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primaryText)
            ForEach(ingredients) { item in
                HStack(spacing: 8) {
                    Circle().fill(Color.brand.opacity(0.7)).frame(width: 6, height: 6)
                    Text(item.name)
                        .font(.footnote)
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(Int(item.estimatedGrams)) g")
                        .font(.caption2)
                        .foregroundStyle(Color.secondaryText)
                    Text("\(item.calories) kcal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.brand)
                        .frame(minWidth: 56, alignment: .trailing)
                }
                .padding(.vertical, 2)
                if item.id != ingredients.last?.id {
                    Divider().overlay(Color.black.opacity(0.05))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}

// MARK: - Kartu What-If (proaktif setelah scan)

struct WhatIfCard: View {
    let alternatives: [WhatIfAlternative]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What-If Simulation", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline).foregroundStyle(Color.primaryText)
            ForEach(alternatives) { alt in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(alt.swapFrom) → \(alt.swapTo)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("-\(alt.calorieSaved) kcal")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.brand)
                            .fixedSize()
                    }
                    Text(alt.reason)
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryText)
                }
                .padding(12)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - Kartu Portion Hint

struct PortionHintCard: View {
    let hint: PortionHint

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.dashed")
                .font(.title3).foregroundStyle(Color.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "Estimated portion: %.1f×", hint.estimatedPortion))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primaryText)
                Text(hint.suggestion)
                    .font(.footnote).foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .cardStyle(cornerRadius: 18)
    }
}

// MARK: - Tombol Voice Correction

/// Tap untuk mulai/berhenti merekam; saat berhenti, transkrip dikirim ke handler.
struct VoiceCorrectionButton: View {
    /// Dipanggil dengan transkrip final saat rekaman dihentikan.
    var onTranscript: (String) async -> Void

    @StateObject private var speech = SpeechTranscriber()

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Label(speech.isRecording ? "Stop & Correct" : "Correct by Voice",
                  systemImage: speech.isRecording ? "stop.circle.fill" : "mic.fill")
        }
        .buttonStyle(GlassButtonStyle())
        .overlay(alignment: .bottom) {
            if speech.isRecording && !speech.transcript.isEmpty {
                Text(speech.transcript)
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                    .offset(y: 22)
            }
        }
    }

    private func toggle() async {
        if speech.isRecording {
            let transcript = speech.stop()
            await onTranscript(transcript)
        } else {
            guard await speech.requestAuthorization() else {
                speech.errorMessage = "Microphone/speech permission denied."
                return
            }
            speech.start()
        }
    }
}
