//
//  PersistenceAgent.swift
//  foodScan
//
//  ╔══════════════════════════════════════════════════════════════════════╗
//  ║ AGENT 3 — PERSISTENCE AGENT                                           ║
//  ╠══════════════════════════════════════════════════════════════════════╣
//  ║ PERAN : Menyimpan & mengelola riwayat scan makanan.                   ║
//  ║ SKILL : - Menyimpan ScanRecord (JSON / Core Data / mock via protocol) ║
//  ║         - Memuat seluruh riwayat                                      ║
//  ║         - Menghapus satu entri / mengosongkan riwayat                 ║
//  ║ INPUT : (CalorieEstimate, imageFileName?)                              ║
//  ║ OUTPUT: ScanRecord yang sudah tersimpan                               ║
//  ║ KOLAB : Menerima output Agent 2; riwayat yang dikelolanya menjadi     ║
//  ║         sumber data untuk Agent 4 (Recommendation).                  ║
//  ╚══════════════════════════════════════════════════════════════════════╝
//
//  TICKET #A3
//   - As: pengguna
//   - I want: setiap hasil scan tersimpan
//   - So that: saya bisa melihat riwayat & total kalori harian
//   - Acceptance: data bertahan setelah app ditutup; bisa dihapus.
//

import Foundation

/// Input gabungan untuk Agent ini.
struct PersistenceInput {
    let estimate: CalorieEstimate
    let imageFileName: String?
}

final class PersistenceAgent: Agent {
    let name = "PersistenceAgent"
    let role = "Menyimpan dan mengelola riwayat scan makanan secara persisten."
    let skills = [
        "Menyimpan ScanRecord ke storage (JSON/Core Data)",
        "Memuat & menghapus riwayat",
        "Menyediakan data riwayat untuk Recommendation Agent"
    ]

    private let store: HistoryStoring

    init(store: HistoryStoring) {
        self.store = store
    }

    func perform(_ input: PersistenceInput) async throws -> ScanRecord {
        let e = input.estimate
        let record = ScanRecord(
            foodLabel: e.foodLabel,
            displayName: e.displayName,
            calories: e.caloriesPerServing,
            confidence: e.confidence,
            imageFileName: input.imageFileName
        )
        try store.save(record)
        return record
    }

    // Skill tambahan yang dipakai langsung oleh HistoryViewModel.
    func allRecords() -> [ScanRecord] { store.loadAll() }
    func add(_ record: ScanRecord) throws { try store.save(record) }
    func update(_ record: ScanRecord) throws { try store.update(record) }
    func delete(id: UUID) throws { try store.delete(id: id) }
    func clearAll() throws { try store.clear() }
}
