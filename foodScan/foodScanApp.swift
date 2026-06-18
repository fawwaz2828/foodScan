//
//  foodScanApp.swift
//  foodScan
//
//  Entry point. Membuat SATU AgentCoordinator yang dipakai bersama oleh
//  semua layar, lalu menyuntikkannya ke ViewModel. Ini menjamin scan baru
//  langsung tercermin di Home & Riwayat (state konsisten).
//

import SwiftUI

@main
struct foodScanApp: App {

    // Coordinator tunggal untuk seluruh app.
    @StateObject private var container = AppContainer()

    init() {
        // Nav/tab bar transparan agar latar glassmorphism terlihat.
        AppearanceConfigurator.apply()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
                .environmentObject(container.settings)
                .preferredColorScheme(.light) // tema terang (ungu/lavender)
                .task {
                    // Agent 4 butuh izin notifikasi.
                    RecommendationAgent.requestNotificationPermission()
                }
        }
    }
}

/// Wadah dependency (composition root) yang memegang Coordinator & ViewModel.
@MainActor
final class AppContainer: ObservableObject {
    let coordinator: AgentCoordinator
    let scanVM: ScanViewModel
    let historyVM: HistoryViewModel
    let settings: UserSettings

    init() {
        // useMockClassifier akan otomatis dilewati bila model nyata tersedia;
        // Coordinator sudah punya fallback ke mock saat model belum ada.
        let coordinator = AgentCoordinator.makeDefault()
        let settings = UserSettings()
        coordinator.updateDailyTarget(settings.dailyCalorieTarget)
        self.coordinator = coordinator
        self.settings = settings
        self.scanVM = ScanViewModel(coordinator: coordinator)
        self.historyVM = HistoryViewModel(coordinator: coordinator, settings: settings)
    }
}
