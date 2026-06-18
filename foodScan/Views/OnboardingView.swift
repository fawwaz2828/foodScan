//
//  OnboardingView.swift
//  foodScan
//
//  Alur onboarding bertahap (gaya Cal AI): mengumpulkan profil lalu menghitung
//  target kalori & macro otomatis. Ditampilkan saat onboarding belum selesai.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var settings: UserSettings
    @State private var step = 0

    private let lastStep = 4

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                progressBar
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        switch step {
                        case 0: sexStep
                        case 1: bodyStep
                        case 2: activityStep
                        case 3: goalStep
                        default: summaryStep
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .appContentWidth()
                }
                footer
                    .appContentWidth()
            }
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: Progress

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0...lastStep, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.brand : Color.brandSoft)
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: Steps

    private var sexStep: some View {
        stepContainer(title: "Sex", subtitle: "Used to calculate your calorie needs.") {
            ForEach(BiologicalSex.allCases) { option in
                choiceRow(option.label, selected: settings.sex == option) { settings.sex = option }
            }
        }
    }

    private var bodyStep: some View {
        stepContainer(title: "Body data", subtitle: "Your age, height, and weight.") {
            stepper("Age", value: "\(settings.age) yr") { settings.age = max(13, settings.age - 1) } plus: { settings.age = min(100, settings.age + 1) }
            stepper("Height", value: String(format: "%.0f cm", settings.heightCm)) { settings.heightCm = max(120, settings.heightCm - 1) } plus: { settings.heightCm = min(220, settings.heightCm + 1) }
            stepper("Weight", value: String(format: "%.1f kg", settings.weightKg)) { settings.weightKg = max(30, settings.weightKg - 0.5) } plus: { settings.weightKg = min(250, settings.weightKg + 0.5) }
        }
    }

    private var activityStep: some View {
        stepContainer(title: "Activity level", subtitle: "How often do you move/exercise?") {
            ForEach(ActivityLevel.allCases) { option in
                choiceRow(option.label, selected: settings.activity == option) { settings.activity = option }
            }
        }
    }

    private var goalStep: some View {
        stepContainer(title: "Your goal", subtitle: "Which way do you want your weight to go?") {
            ForEach(WeightGoal.allCases) { option in
                choiceRow(option.label, selected: settings.goal == option) { settings.goal = option }
            }
        }
    }

    private var summaryStep: some View {
        stepContainer(title: "Your daily plan", subtitle: "Calculated from your profile & goal.") {
            let cals = settings.previewCalorieTarget
            let macros = GoalCalculator.macros(calories: cals, weightKg: settings.weightKg, goal: settings.goal)
            VStack(spacing: 14) {
                bigStat("\(cals)", "kcal / day", Color.brand)
                HStack(spacing: 10) {
                    macroPill("Protein", macros.protein, .macroProtein)
                    macroPill("Carbs", macros.carbs, .macroCarbs)
                    macroPill("Fat", macros.fat, .macroFat)
                }
                Text("By continuing, you agree that food photos you scan are sent to OpenAI to estimate nutrition. Your history & profile stay on this device.")
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(GlassButtonStyle())
            }
            Button(step == lastStep ? "Start" : "Next") {
                if step == lastStep {
                    settings.recomputeTargets()
                    settings.onboardingCompleted = true
                } else {
                    step += 1
                }
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
        }
        .padding(.horizontal, 24)
    }

    // MARK: Komponen

    private func stepContainer<Content: View>(title: String, subtitle: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title.weight(.bold)).foregroundStyle(Color.primaryText)
            Text(subtitle).font(.subheadline).foregroundStyle(Color.secondaryText)
            VStack(spacing: 10) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choiceRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.headline).foregroundStyle(Color.primaryText)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.brand : Color.secondaryText)
            }
            .padding(16)
            .background(selected ? Color.brandSoft : Color.cardBackground,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.brand : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    private func stepper(_ label: String, value: String,
                         minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.headline).foregroundStyle(Color.primaryText)
            Spacer()
            Button { minus() } label: { Image(systemName: "minus.circle.fill") }
            Text(value).font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primaryText).frame(minWidth: 72)
            Button { plus() } label: { Image(systemName: "plus.circle.fill") }
        }
        .tint(Color.brand)
        .padding(16)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func bigStat(_ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(color)
            Text(unit).font(.subheadline).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .cardStyle(cornerRadius: 22)
    }

    private func macroPill(_ label: String, _ grams: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(grams)g").font(.headline.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
