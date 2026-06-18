//
//  HistoryViewModel.swift
//  foodScan
//
//  Menyediakan data riwayat (dari Persistence Agent) & rekomendasi harian
//  (dari Recommendation Agent) ke layar Home dan Riwayat.
//

import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {

    @Published var records: [ScanRecord] = []
    @Published var recommendation: DailyRecommendation?
    @Published var personalAdvice: PersonalAdvice?   // RAG 7 hari via Groq

    private let coordinator: AgentCoordinator
    private let enhancedRec: EnhancedRecommendationAgent
    private let settings: UserSettings?

    init(coordinator: AgentCoordinator,
         settings: UserSettings? = nil,
         enhancedRec: EnhancedRecommendationAgent = EnhancedRecommendationAgent()) {
        self.coordinator = coordinator
        self.settings = settings
        self.enhancedRec = enhancedRec
    }

    /// Muat ulang riwayat, rekomendasi harian, & saran personal (Groq).
    func refresh() async {
        // Pakai target kalori terbaru pilihan pengguna sebelum menghitung ulang.
        if let target = settings?.dailyCalorieTarget {
            coordinator.updateDailyTarget(target)
        }
        records = coordinator.persistence.allRecords()
        recommendation = try? await coordinator.recomputeRecommendation()
        // Saran personal dari Groq (diam-diam gagal bila API key belum diset).
        personalAdvice = try? await enhancedRec.perform(records)
    }

    /// Log makanan manual via teks (tanpa foto): Groq mengestimasi gizi, lalu
    /// disimpan sebagai entri baru. Mengembalikan true bila berhasil.
    func logManualFood(description: String) async -> Bool {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let est = try await OpenAIService.shared.requestManualEstimate(description: trimmed)
            let nutrition = est.nutrition
            let record = ScanRecord(
                foodLabel: est.name.lowercased(),
                displayName: est.name,
                calories: est.calories,
                confidence: 1.0,
                date: Date(),
                imageFileName: nil,
                portionRatio: 1.0,
                nutrition: nutrition
            )
            try? coordinator.persistence.add(record)
            await refresh()
            return true
        } catch {
            return false
        }
    }

    /// Catat ulang makanan yang sama sebagai entri baru bertanggal sekarang
    /// (tombol "+" di daftar Recent Meals di Home).
    func logAgain(_ record: ScanRecord) {
        let copy = ScanRecord(
            foodLabel: record.foodLabel,
            displayName: record.displayName,
            calories: record.calories,
            confidence: record.confidence,
            date: Date(),
            imageFileName: record.imageFileName,
            portionRatio: record.portionRatio,
            nutrition: record.nutrition
        )
        try? coordinator.persistence.add(copy)
        Task { await refresh() }
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let record = records[index]
            try? coordinator.persistence.delete(id: record.id)
        }
        Task { await refresh() }
    }

    func delete(_ record: ScanRecord) {
        try? coordinator.persistence.delete(id: record.id)
        Task { await refresh() }
    }

    func clearAll() {
        try? coordinator.persistence.clearAll()
        Task { await refresh() }
    }

    // MARK: - Ringkasan harian (Cal AI)

    private var todayRecords: [ScanRecord] {
        records.filter { Calendar.current.isDateInToday($0.date) }
    }

    /// Total kalori hari ini (dipakai kartu ringkasan di Home).
    var totalToday: Int {
        todayRecords.reduce(0) { $0 + $1.calories }
    }

    /// Total macro hari ini (gram) — dijumlahkan dari record yang punya data gizi.
    var todayProtein: Int { Int(todayRecords.compactMap { $0.nutrition?.proteinGram }.reduce(0, +)) }
    var todayCarbs: Int { Int(todayRecords.compactMap { $0.nutrition?.carbsGram }.reduce(0, +)) }
    var todayFat: Int { Int(todayRecords.compactMap { $0.nutrition?.fatGram }.reduce(0, +)) }

    /// Makanan hari ini dikelompokkan per waktu makan.
    func todayMeals(for time: MealTime) -> [ScanRecord] {
        todayRecords.filter { $0.mealTime == time }
    }

    /// Memperbarui satu record (dipakai layar Edit) lalu refresh.
    func update(_ record: ScanRecord) {
        try? coordinator.persistence.update(record)
        Task { await refresh() }
    }

    /// Jumlah hari beruntun (hingga hari ini) dengan minimal satu catatan.
    var streak: Int {
        let cal = Calendar.current
        let loggedDays = Set(records.map { cal.startOfDay(for: $0.date) })
        guard !loggedDays.isEmpty else { return 0 }
        var count = 0
        var day = cal.startOfDay(for: Date())
        // Jika hari ini belum ada catatan, mulai hitung dari kemarin.
        if !loggedDays.contains(day) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        while loggedDays.contains(day) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }
}
