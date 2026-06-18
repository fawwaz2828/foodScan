//
//  EnhancedRecommendationAgent.swift
//  foodScan
//
//  ╔══════════════════════════════════════════════════════════════════════╗
//  ║ AGENT 6 — ENHANCED RECOMMENDATION AGENT (RAG via ChatGPT)              ║
//  ╠══════════════════════════════════════════════════════════════════════╣
//  ║ PERAN : Saran personal + simulasi What-If dari riwayat (RAG).         ║
//  ║ SKILL : - Membaca riwayat 7 hari (dari Persistence Agent)             ║
//  ║         - ChatGPT: saran "karena kamu makan X 4x..." + what-if        ║
//  ║         - ChatGPT: 2 alternatif swap proaktif tiap selesai scan       ║
//  ║         - Menjadwalkan notifikasi 18:00 bila sisa kalori < 500        ║
//  ║ INPUT : [ScanRecord]  → OUTPUT: PersonalAdvice                         ║
//  ║ KOLAB : Mengonsumsi data Agent 3; output tampil di Home & kartu scan. ║
//  ╚══════════════════════════════════════════════════════════════════════╝
//
//  TICKET #A6
//   - As: pengguna
//   - I want: saran personal berbasis pola makan + simulasi "what if"
//   - So that: saya tahu langkah konkret memperbaiki pola makan
//   - Acceptance: saran merujuk pola 7 hari nyata; What-If memberi tepat 2
//     alternatif swap; reminder malam dijadwalkan saat sisa kalori < 500.
//

import Foundation
import UserNotifications

final class EnhancedRecommendationAgent: Agent {
    let name = "EnhancedRecommendationAgent"
    let role = "Saran personal & simulasi what-if berbasis riwayat via ChatGPT."
    let skills = [
        "RAG riwayat 7 hari → saran personal",
        "Simulasi What-If (2 alternatif swap)",
        "Penjadwalan notifikasi malam (18:00) berbasis sisa kalori"
    ]

    private let ai: OpenAIService
    private let dailyTarget: Int
    init(ai: OpenAIService = .shared, dailyTarget: Int = 2000) {
        self.ai = ai
        self.dailyTarget = dailyTarget
    }

    /// Saran personal dari riwayat 7 hari terakhir.
    func perform(_ records: [ScanRecord]) async throws -> PersonalAdvice {
        let last7 = recordsWithinLast7Days(records)
        return try await ai.requestRecommendation(history: last7, dailyTarget: dailyTarget)
    }

    /// Simulasi What-If proaktif (dipanggil setelah scan).
    func whatIf(lastScanned: String, todayTotal: Int, last3Meals: [String]) async throws -> [WhatIfAlternative] {
        let remaining = max(dailyTarget - todayTotal, 0)
        return try await ai.requestWhatIf(
            lastScannedFood: lastScanned,
            todayTotal: todayTotal,
            dailyGoal: dailyTarget,
            remainingCalories: remaining,
            last3Meals: last3Meals
        )
    }

    /// Notifikasi lokal jam 18:00 bila sisa kalori harian < 500.
    func scheduleEveningReminder(todayTotal: Int) {
        let remaining = dailyTarget - todayTotal
        let center = UNUserNotificationCenter.current()
        let id = "evening_calorie_reminder"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard remaining < 500 else { return } // tidak relevan → tidak menjadwalkan

        let content = UNMutableNotificationContent()
        content.title = "FoodScan — Calories Running Low"
        content.body = "You have \(max(remaining, 0)) kcal left for today. Go for a light dinner."
        content.sound = .default

        var when = DateComponents()
        when.hour = 18
        when.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func recordsWithinLast7Days(_ records: [ScanRecord]) -> [ScanRecord] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return records }
        return records.filter { $0.date >= cutoff }
    }
}
