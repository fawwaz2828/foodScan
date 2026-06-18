//
//  RecommendationAgent.swift
//  foodScan
//
//  ╔══════════════════════════════════════════════════════════════════════╗
//  ║ AGENT 4 — RECOMMENDATION / NOTIFICATION AGENT                         ║
//  ╠══════════════════════════════════════════════════════════════════════╣
//  ║ PERAN : Menganalisis total kalori HARI INI & memberi saran.          ║
//  ║ SKILL : - Menjumlahkan kalori untuk tanggal hari ini                 ║
//  ║         - Membandingkan dengan target harian                         ║
//  ║         - Menghasilkan pesan saran + status (low/onTrack/high)        ║
//  ║         - (Opsional) menjadwalkan notifikasi lokal                    ║
//  ║ INPUT : [ScanRecord]                                                   ║
//  ║ OUTPUT: DailyRecommendation                                           ║
//  ║ KOLAB : Mengonsumsi riwayat dari Persistence Agent; hasilnya          ║
//  ║         ditampilkan di Home & memicu notifikasi bila melebihi target. ║
//  ╚══════════════════════════════════════════════════════════════════════╝
//
//  TICKET #A4
//   - As: pengguna
//   - I want: tahu apakah konsumsi kalori hari ini berlebih
//   - So that: saya bisa menjaga pola makan
//   - Acceptance: total hanya menghitung record bertanggal hari ini;
//     pesan berbeda untuk low/onTrack/high.
//

import Foundation
import UserNotifications

final class RecommendationAgent: Agent {
    let name = "RecommendationAgent"
    let role = "Memberi rekomendasi & notifikasi berdasarkan total kalori harian."
    let skills = [
        "Agregasi kalori harian",
        "Evaluasi terhadap target harian",
        "Pembuatan pesan saran kontekstual",
        "Penjadwalan notifikasi lokal (UserNotifications)"
    ]

    /// Target kalori harian (dapat diubah pengguna lewat menu Target Kalori).
    var dailyTarget: Int

    init(dailyTarget: Int = 2000) {
        self.dailyTarget = dailyTarget
    }

    func perform(_ input: [ScanRecord]) async throws -> DailyRecommendation {
        let calendar = Calendar.current
        let todayTotal = input
            .filter { calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.calories }

        let status: CalorieStatus
        let message: String
        let ratio = Double(todayTotal) / Double(dailyTarget)

        switch ratio {
        case ..<0.5:
            status = .low
            message = "Intake so far is \(todayTotal) kcal. You still have \(dailyTarget - todayTotal) kcal left — don't skip a nutritious meal."
        case 0.5..<1.0:
            status = .onTrack
            message = "Nice! \(todayTotal) kcal today, still within your \(dailyTarget) kcal target."
        default:
            status = .high
            message = "Heads up: \(todayTotal) kcal exceeds your \(dailyTarget) kcal target. Consider a lighter portion."
        }

        let recommendation = DailyRecommendation(
            totalCaloriesToday: todayTotal,
            dailyTarget: dailyTarget,
            status: status,
            message: message
        )

        // Skill tambahan: kirim notifikasi lokal bila melebihi target
        // (hanya jika pengguna mengaktifkan notifikasi di menu Notifikasi).
        let notificationsOn = UserDefaults.standard.bool(forKey: "settings.notificationsEnabled")
        if status == .high && notificationsOn {
            scheduleNotification(message: message)
        }
        return recommendation
    }

    /// Menjadwalkan notifikasi lokal. Memerlukan izin (diminta di app launch).
    private func scheduleNotification(message: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "FoodScan — Daily Calories"
        content.body = message
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        center.add(request)
    }

    /// Dipanggil sekali saat app start untuk meminta izin notifikasi.
    static func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
