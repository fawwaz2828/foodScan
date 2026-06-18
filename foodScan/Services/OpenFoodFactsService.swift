//
//  OpenFoodFactsService.swift
//  foodScan
//
//  Klien Open Food Facts (gratis, TANPA API key) untuk mencari produk kemasan
//  berdasarkan barcode. Tidak butuh pendaftaran — cukup memanggil endpoint dan
//  mengirim header `User-Agent` sesuai etika OFF.
//
//  Endpoint: https://world.openfoodfacts.org/api/v2/product/{barcode}.json
//

import Foundation

enum OpenFoodFactsError: LocalizedError {
    case http(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .http(let c): return "Open Food Facts HTTP \(c)."
        case .decoding: return "Gagal membaca data produk."
        }
    }
}

/// Hasil pencarian satu produk (sudah dipetakan ke gizi internal).
struct ScannedProduct {
    let name: String
    let calories: Int
    let nutrition: NutritionalInfo
}

struct OpenFoodFactsService {

    static let shared = OpenFoodFactsService()

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    /// Cari produk berdasarkan barcode. Mengembalikan `nil` bila tidak ditemukan.
    func lookup(barcode: String) async throws -> ScannedProduct? {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty,
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.setValue("FoodScan/1.0 (iOS app)", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw OpenFoodFactsError.http(status) }

        guard let decoded = try? JSONDecoder().decode(OFFResponse.self, from: data) else {
            throw OpenFoodFactsError.decoding
        }
        guard decoded.status == 1, let product = decoded.product else { return nil }

        return Self.map(product)
    }

    // MARK: - Mapping OFF → ScannedProduct

    private static func map(_ p: OFFProduct) -> ScannedProduct {
        let n = p.nutriments ?? [:]
        // Prioritaskan nilai per-porsi; bila tak ada, pakai per-100 g.
        func value(_ base: String) -> Double? {
            n["\(base)_serving"]?.value ?? n["\(base)_100g"]?.value
        }
        let perServing = n["energy-kcal_serving"]?.value != nil
        let calories = Int((value("energy-kcal") ?? 0).rounded())
        let protein = value("proteins") ?? 0
        let carbs = value("carbohydrates") ?? 0
        let fat = value("fat") ?? 0
        let fiber = value("fiber") ?? 0

        let name: String = {
            let pn = p.productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !pn.isEmpty { return pn }
            if let b = p.brands, !b.isEmpty { return b }
            return "Unknown product"
        }()

        var notes: [String] = []
        if let b = p.brands, !b.isEmpty { notes.append(b) }
        notes.append(perServing
                     ? "Values per serving\(p.servingSize.map { " (\($0))" } ?? "")"
                     : "Values per 100 g")
        let insight = notes.joined(separator: " · ")

        let nutrition = NutritionalInfo(
            proteinGram: protein, carbsGram: carbs, fatGram: fat, fiberGram: fiber,
            healthScore: healthScore(from: p.nutriscoreGrade), insight: insight
        )
        return ScannedProduct(name: name, calories: calories, nutrition: nutrition)
    }

    /// Nutri-Score (a–e) → skor 1–10. Default 5 bila tidak tersedia.
    private static func healthScore(from grade: String?) -> Double {
        switch grade?.lowercased() {
        case "a": return 9
        case "b": return 7
        case "c": return 5
        case "d": return 3
        case "e": return 1
        default:  return 5
        }
    }
}

// MARK: - DTO Open Food Facts (v2)

private struct OFFResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

private struct OFFProduct: Decodable {
    let productName: String?
    let brands: String?
    let nutriscoreGrade: String?
    let servingSize: String?
    let nutriments: [String: FlexNumber]?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case nutriscoreGrade = "nutriscore_grade"
        case servingSize = "serving_size"
        case nutriments
    }
}

/// OFF kadang mengembalikan angka sebagai Number, kadang String. Terima keduanya.
private struct FlexNumber: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
}
