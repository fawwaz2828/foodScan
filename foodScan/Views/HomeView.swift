//
//  HomeView.swift
//  foodScan
//
//  Dashboard harian bertema merah-putih (gaya Cal AI):
//   - Header sapaan + streak + notifikasi
//   - Judul besar dua-warna + search
//   - Ring kalori harian (sisa) + ring macro (protein/karbo/lemak)
//   - Makanan hari ini dikelompokkan per waktu makan
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var scanVM: ScanViewModel
    @EnvironmentObject private var settings: UserSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var searchText = ""
    @State private var detailRecord: ScanRecord?
    @State private var showManualLog = false

    private var target: Int { viewModel.recommendation?.dailyTarget ?? settings.dailyCalorieTarget }
    private var remaining: Int { max(target - viewModel.totalToday, 0) }
    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(viewModel.totalToday) / Double(target), 1)
    }

    private func meals(for time: MealTime) -> [ScanRecord] {
        viewModel.todayMeals(for: time).filter {
            searchText.isEmpty || $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var hasAnyMeal: Bool {
        MealTime.allCases.contains { !meals(for: $0).isEmpty }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        heroHeading
                        searchBar
                        calorieCard
                        macroCard
                        mealsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                    .appContentWidth()
                }
            }
            .navigationBarHidden(true)
            .task { await viewModel.refresh() }
            .refreshable { await viewModel.refresh() }
            .sheet(item: $detailRecord) { record in
                MealDetailSheet(record: record, dailyTarget: target, viewModel: viewModel)
            }
            .sheet(isPresented: $showManualLog) {
                ManualLogView(viewModel: viewModel)
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.brand)
            VStack(alignment: .leading, spacing: 1) {
                Text(greeting).font(.caption).foregroundStyle(Color.secondaryText)
                Text(settings.userName).font(.headline).foregroundStyle(Color.primaryText)
            }
            Spacer()
            if viewModel.streak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                    Text("\(viewModel.streak)")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brand)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.brandSoft, in: Capsule())
            }
            Image(systemName: "bell")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primaryText)
                .frame(width: 42, height: 42)
                .background(Color.cardBackground, in: Circle())
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning!"
        case 12..<17: return "Good afternoon!"
        default:      return "Good evening!"
        }
    }

    private var heroHeading: some View {
        (Text("Let's Check Your\n").foregroundColor(Color.primaryText)
         + Text("Meal Together").foregroundColor(Color.secondaryText.opacity(0.7)))
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.secondaryText)
            TextField("Search today's meals", text: $searchText)
                .foregroundStyle(Color.primaryText)
            Image(systemName: "sparkles")
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
    }

    // MARK: Ring kalori

    private var calorieCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Today's intake", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("\(viewModel.totalToday)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("of \(target) kcal target")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            ZStack {
                Circle().stroke(.white.opacity(0.3), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: progress)
                VStack(spacing: 0) {
                    Text("\(remaining)").font(.headline.weight(.bold)).foregroundStyle(.white)
                    Text("left").font(.caption2).foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 86, height: 86)
        }
        .padding(20)
        .background(Color.brandGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.brand.opacity(0.3), radius: 16, x: 0, y: 10)
    }

    // MARK: Ring macro

    private var macroCard: some View {
        HStack(spacing: 10) {
            MacroRing(label: "Protein", value: viewModel.todayProtein,
                      target: settings.proteinTarget, color: .macroProtein)
            MacroRing(label: "Carbs", value: viewModel.todayCarbs,
                      target: settings.carbsTarget, color: .macroCarbs)
            MacroRing(label: "Fat", value: viewModel.todayFat,
                      target: settings.fatTarget, color: .macroFat)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .cardStyle(cornerRadius: 22, padding: 12)
    }

    // MARK: Makanan per waktu makan

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Meals").font(.headline).foregroundStyle(Color.primaryText)
                Spacer()
                Button { showManualLog = true } label: {
                    Label("Log", systemImage: "square.and.pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.brand)
                }
                .buttonStyle(.plain)
            }
            if !hasAnyMeal {
                emptyMeals
            } else {
                ForEach(MealTime.allCases) { time in
                    let items = meals(for: time)
                    if !items.isEmpty {
                        mealTimeSection(time, items)
                    }
                }
            }
        }
    }

    private func mealTimeSection(_ time: MealTime, _ items: [ScanRecord]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: time.icon).font(.subheadline).foregroundStyle(Color.brand)
                Text(time.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primaryText)
                Spacer()
                Text("\(items.reduce(0) { $0 + $1.calories }) kcal")
                    .font(.caption).foregroundStyle(Color.secondaryText)
            }
            ForEach(items) { record in
                MealPickCard(record: record) { detailRecord = record }
            }
        }
    }

    private var emptyMeals: some View {
        VStack(spacing: 8) {
            Image(systemName: "viewfinder").font(.title2).foregroundStyle(Color.brand)
            Text(searchText.isEmpty
                 ? "No meals logged today. Open the Scan tab to start."
                 : "Nothing matches your search.")
                .font(.footnote).foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(cornerRadius: 20)
    }
}

// MARK: - Kartu meal pick (merah lembut, gaya mockup)

private struct MealPickCard: View {
    let record: ScanRecord
    var onDetails: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(record.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").font(.caption2).foregroundStyle(Color.brand)
                    Text("\(record.calories) kcal")
                        .font(.caption).foregroundStyle(Color.secondaryText)
                }
                Button(action: onDetails) {
                    HStack(spacing: 4) {
                        Text("See Details")
                        Image(systemName: "arrow.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.brand, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 4)
            Group {
                if let image = ImageStore.load(record.imageFileName) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.brandSoft
                        Image(systemName: "fork.knife").foregroundStyle(Color.brand)
                    }
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(14)
        .background(Color.brandSoft.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Detail makanan (Cal AI) dari Home

struct MealDetailSheet: View {
    @State private var record: ScanRecord
    let dailyTarget: Int
    let viewModel: HistoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showChat = false
    @State private var showEdit = false

    init(record: ScanRecord, dailyTarget: Int, viewModel: HistoryViewModel) {
        _record = State(initialValue: record)
        self.dailyTarget = dailyTarget
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if let image = ImageStore.load(record.imageFileName) {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(height: 220).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.displayName)
                            .font(.title2.weight(.bold)).foregroundStyle(Color.primaryText)
                        Label("Total \(record.calories) kcal", systemImage: "flame.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.brand)
                    }

                    if let nutrition = record.nutrition {
                        MacroCardsRow(nutrition: nutrition, dailyTarget: dailyTarget)
                        HealthyScoreBar(score: nutrition.healthScore)
                        if !nutrition.insight.isEmpty {
                            Text(nutrition.insight)
                                .font(.footnote).foregroundStyle(Color.secondaryText)
                        }
                        if let ingredients = nutrition.ingredients, !ingredients.isEmpty {
                            IngredientsCard(ingredients: ingredients)
                        }
                    } else {
                        Text("Nutrition details aren't available for this meal yet.")
                            .font(.footnote).foregroundStyle(Color.secondaryText)
                    }

                    Button {
                        showChat = true
                    } label: {
                        Label("Ask AI about this meal", systemImage: "message.fill")
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                }
                .padding(20)
                .appContentWidth()
            }
            .background(AppBackground())
            .navigationTitle("Food Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Color.brand)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showEdit = true }.tint(Color.brand)
                }
            }
            .sheet(isPresented: $showChat) {
                MealChatSheet(record: record)
            }
            .sheet(isPresented: $showEdit) {
                EditMealView(record: record) { updated in
                    record = updated
                    viewModel.update(updated)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Edit entri (nama, kalori, porsi, waktu makan)

struct EditMealView: View {
    let record: ScanRecord
    var onSave: (ScanRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var calories: Int
    @State private var mealTime: MealTime

    init(record: ScanRecord, onSave: @escaping (ScanRecord) -> Void) {
        self.record = record
        self.onSave = onSave
        _name = State(initialValue: record.displayName)
        _calories = State(initialValue: record.calories)
        _mealTime = State(initialValue: record.mealTime)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Meal") {
                    TextField("Name", text: $name)
                    Stepper(value: $calories, in: 0...5000, step: 10) {
                        HStack {
                            Text("Calories")
                            Spacer()
                            Text("\(calories) kcal").foregroundStyle(Color.secondaryText)
                        }
                    }
                    Picker("Meal time", selection: $mealTime) {
                        ForEach(MealTime.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let updated = record.applying(
                            displayName: trimmed.isEmpty ? nil : trimmed,
                            calories: calories,
                            mealTime: mealTime
                        )
                        onSave(updated)
                        dismiss()
                    }.tint(Color.brand)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Chat AI untuk satu record (dipakai dari detail makanan & riwayat)

struct MealChatSheet: View {
    let record: ScanRecord
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [FoodChatMessage] = []
    @State private var input = ""
    @State private var isAsking = false

    private var suggestions: [String] {
        [
            "Is this a healthy choice?",
            "What's a lighter alternative to \(record.displayName)?",
            "How can I burn off these calories?"
        ]
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(messages) { msg in
                            HStack {
                                if msg.role == .assistant {
                                    bubble(msg.text, isUser: false)
                                    Spacer(minLength: 24)
                                } else {
                                    Spacer(minLength: 24)
                                    bubble(msg.text, isUser: true)
                                }
                            }
                        }
                        if isAsking {
                            HStack(spacing: 8) {
                                ProgressView().tint(Color.brand)
                                Text("AI is typing…")
                                    .font(.caption).foregroundStyle(Color.secondaryText)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { prompt in
                            Button(prompt) { ask(prompt) }
                                .font(.caption).lineLimit(1)
                                .buttonStyle(GlassButtonStyle())
                                .disabled(isAsking)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                HStack(spacing: 8) {
                    TextField("Ask about this food…", text: $input)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let text = input
                        input = ""
                        ask(text)
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAsking)
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
            .navigationTitle("Ask AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.tint(Color.brand)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAsking else { return }
        messages.append(.init(role: .user, text: trimmed))
        isAsking = true
        Task {
            do {
                let answer = try await OpenAIService.shared.requestFoodChat(
                    foodName: record.displayName,
                    calories: record.calories,
                    portion: record.portionRatio,
                    nutrition: record.nutrition,
                    userQuestion: trimmed
                )
                messages.append(.init(role: .assistant, text: answer))
            } catch {
                messages.append(.init(role: .assistant, text: "Sorry, I can't answer right now. Please try again shortly."))
            }
            isAsking = false
        }
    }

    private func bubble(_ text: String, isUser: Bool) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(isUser ? Color.white : Color.primaryText)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isUser ? Color.brand : Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            )
    }
}
