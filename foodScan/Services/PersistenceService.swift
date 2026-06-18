//
//  PersistenceService.swift
//  foodScan
//
//  Lapisan penyimpanan untuk PersistenceAgent.
//  Implementasi default menyimpan riwayat sebagai file JSON di Documents
//  directory (alternatif sederhana & andal untuk Core Data). Tersedia juga
//  implementasi in-memory untuk unit testing.
//
//  CATATAN: Bila ingin memakai Core Data, cukup buat implementasi lain dari
//  `HistoryStoring` yang membungkus NSManagedObjectContext — Agent tidak perlu
//  diubah karena hanya bergantung pada protocol.
//

import Foundation
import UIKit

/// Kontrak penyimpanan riwayat. Memungkinkan swap JSON <-> Core Data <-> mock.
protocol HistoryStoring {
    func save(_ record: ScanRecord) throws
    func loadAll() -> [ScanRecord]
    func update(_ record: ScanRecord) throws
    func delete(id: UUID) throws
    func clear() throws
}

/// Implementasi berbasis file JSON di Documents directory.
final class FileHistoryStore: HistoryStoring {

    private let fileName = "scan_history.json"
    private let fileManager = FileManager.default

    private var fileURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    func save(_ record: ScanRecord) throws {
        var all = loadAll()
        all.insert(record, at: 0) // terbaru di atas
        try persist(all)
    }

    func loadAll() -> [ScanRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ScanRecord].self, from: data)) ?? []
    }

    func update(_ record: ScanRecord) throws {
        var all = loadAll()
        if let idx = all.firstIndex(where: { $0.id == record.id }) {
            all[idx] = record
        } else {
            all.insert(record, at: 0)
        }
        try persist(all)
    }

    func delete(id: UUID) throws {
        var all = loadAll()
        all.removeAll { $0.id == id }
        try persist(all)
    }

    func clear() throws {
        try? fileManager.removeItem(at: fileURL)
    }

    private func persist(_ records: [ScanRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw FoodScanError.persistenceFailed(error.localizedDescription)
        }
    }
}

/// Penyimpan gambar ke Documents (mengembalikan nama file untuk direferensi
/// oleh ScanRecord.imageFileName).
enum ImageStore {
    private static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func save(_ image: UIImage) -> String? {
        let name = "scan_\(UUID().uuidString).jpg"
        guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }
        let url = docs.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        return name
    }

    static func load(_ fileName: String?) -> UIImage? {
        guard let fileName else { return nil }
        let url = docs.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

/// Store in-memory untuk unit testing (tanpa menyentuh disk).
final class InMemoryHistoryStore: HistoryStoring {
    private(set) var records: [ScanRecord] = []
    func save(_ record: ScanRecord) throws { records.insert(record, at: 0) }
    func loadAll() -> [ScanRecord] { records }
    func update(_ record: ScanRecord) throws {
        if let idx = records.firstIndex(where: { $0.id == record.id }) { records[idx] = record }
        else { records.insert(record, at: 0) }
    }
    func delete(id: UUID) throws { records.removeAll { $0.id == id } }
    func clear() throws { records.removeAll() }
}
