//
//  MenuFeatureViews.swift
//  foodScan
//
//  Layar detail yang dibuka dari tab Menu: Profil, Target Kalori, Notifikasi,
//  Pengaturan, Bantuan. Semua membaca/menulis ke UserSettings.
//

import SwiftUI

// MARK: - Profil

struct ProfileView: View {
    @EnvironmentObject private var settings: UserSettings

    var body: some View {
        Form {
            Section("Identity") {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Your name", text: $settings.userName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Color.secondaryText)
                }
                Picker("Sex", selection: $settings.sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Body") {
                Stepper(value: $settings.age, in: 13...100) {
                    labeled("Age", "\(settings.age) yr")
                }
                Stepper(value: $settings.heightCm, in: 120...220, step: 1) {
                    labeled("Height", String(format: "%.0f cm", settings.heightCm))
                }
                Stepper(value: $settings.weightKg, in: 30...250, step: 0.5) {
                    labeled("Weight", String(format: "%.1f kg", settings.weightKg))
                }
            }
            Section("Activity & goal") {
                Picker("Activity", selection: $settings.activity) {
                    ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) }
                }
                Picker("Goal", selection: $settings.goal) {
                    ForEach(WeightGoal.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                Button {
                    settings.recomputeTargets()
                } label: {
                    Label("Recalculate target (\(settings.previewCalorieTarget) kcal)",
                          systemImage: "arrow.clockwise")
                }
            } footer: {
                Text("Updates your calorie & macro targets from the latest profile.")
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(Color.secondaryText)
        }
    }
}

// MARK: - Target Kalori

struct TargetView: View {
    @EnvironmentObject private var settings: UserSettings

    var body: some View {
        Form {
            Section {
                Stepper(value: $settings.dailyCalorieTarget, in: 1000...5000, step: 50) {
                    HStack {
                        Image(systemName: "flame.fill").foregroundStyle(Color.brand)
                        Text("\(settings.dailyCalorieTarget) kcal")
                            .font(.headline)
                    }
                }
            } header: {
                Text("Daily calorie target")
            } footer: {
                Text("Derived from your profile, but you can adjust it manually.")
            }

            Section("Macro targets (automatic)") {
                macroRow("Protein", settings.proteinTarget, .macroProtein)
                macroRow("Carbs", settings.carbsTarget, .macroCarbs)
                macroRow("Fat", settings.fatTarget, .macroFat)
            }
        }
        .navigationTitle("Calorie Target")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func macroRow(_ title: String, _ grams: Int, _ color: Color) -> some View {
        HStack {
            Image(systemName: "circle.fill").font(.caption2).foregroundStyle(color)
            Text(title)
            Spacer()
            Text("\(grams) g").foregroundStyle(Color.secondaryText)
        }
    }
}

// MARK: - Notifikasi

struct NotificationsView: View {
    @EnvironmentObject private var settings: UserSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.notificationsEnabled) {
                    Text("Calorie reminder")
                }
                .tint(Color.brand)
            } footer: {
                Text("Send a notification when today's intake exceeds your target.")
            }

            if settings.notificationsEnabled {
                Section {
                    Button {
                        RecommendationAgent.requestNotificationPermission()
                    } label: {
                        Label("Allow notifications", systemImage: "bell.badge")
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Pengaturan

struct SettingsView: View {
    @EnvironmentObject private var settings: UserSettings

    var body: some View {
        Form {
            Section("App") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: appBuild)
            }
            Section("Account") {
                LabeledContent("User", value: settings.userName)
            }
            Section {
                Text("Scanning sends your food photo to OpenAI to estimate nutrition. Meal history and profile stay on this device.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

// MARK: - Bantuan

struct HelpView: View {
    private let faqs: [(String, String)] = [
        ("How do I scan food?",
         "Open the Scan tab in the center, point the camera or pick a photo from your gallery, then wait for the result."),
        ("How is the calorie target calculated?",
         "The target is set manually in the Calorie Target menu. Progress on Home & Statistic compares today's scanned total with that target."),
        ("What is the Healthy Score?",
         "A 1–10 score from the AI rating how healthy a food is based on its nutrition."),
        ("Is my data safe?",
         "Your meal history and profile are stored only on this device. When you scan or ask the AI, the food photo and the related text are sent to OpenAI for analysis — that is required for the feature to work. Nothing else leaves your device."),
        ("Are my food photos sent to the cloud?",
         "Yes. To recognize the meal and estimate nutrition, the photo is sent to OpenAI's API for that single request. Avoid scanning images that contain sensitive or personal information.")
    ]

    var body: some View {
        List {
            ForEach(faqs, id: \.0) { item in
                DisclosureGroup(item.0) {
                    Text(item.1)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}
