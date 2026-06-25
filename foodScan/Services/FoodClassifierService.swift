//
//  FoodClassifierService.swift
//  foodScan
//
//  Service low-level yang membungkus Core ML + Vision.
//  Dipakai oleh `ImageRecognitionAgent`. Sengaja dipisah dari Agent agar:
//   - Agent fokus pada "keputusan/alur", service fokus pada "mekanik ML"
//   - mudah di-mock saat unit testing
//
//  CARA LOAD MODEL .mlmodel:
//  --------------------------------------------------------------
//  1) Download Food101.mlmodel (lihat README repo Food101-CoreML),
//     lalu drag ke project Xcode (centang target "foodScan").
//  2) Saat build, Xcode meng-compile Food101.mlmodel -> Food101.mlmodelc
//     di dalam app bundle.
//  3) Di sini kita TIDAK memakai class auto-generated `Food101()`,
//     melainkan load model secara dinamis lewat URL bundle
//     (`MLModel(contentsOf:)`). Keuntungannya: project tetap BISA
//     di-compile walau file model belum ditambahkan, dan otomatis
//     aktif begitu model tersedia.
//  --------------------------------------------------------------
//

import Foundation
import CoreML
import Vision
import UIKit

/// Abstraksi agar Agent tidak tergantung implementasi konkret.
/// Memudahkan menyuntik `MockFoodClassifier` di test.
protocol FoodClassifying {
    func classify(image: UIImage) async throws -> FoodPrediction
}

/// Implementasi nyata berbasis Core ML + Vision.
final class FoodClassifierService: FoodClassifying {

    /// Nama resource model (tanpa ekstensi). Setelah build menjadi `.mlmodelc`.
    /// Memakai SeeFood.mlmodel (InceptionV3, 101 kelas Food-101, output
    /// `classLabel` + `foodConfidence`). Ganti string ini bila memakai model lain.
    private let modelResourceName = "SeeFood"

    /// VNCoreMLModel di-cache supaya tidak load berulang kali.
    private lazy var vnModel: VNCoreMLModel? = loadModel()

    private func loadModel() -> VNCoreMLModel? {
        // Cari model yang sudah dikompilasi di dalam bundle.
        guard let url = Bundle.main.url(forResource: modelResourceName, withExtension: "mlmodelc") else {
            print("⚠️ [FoodClassifierService] \(modelResourceName).mlmodelc tidak ditemukan di bundle.")
            return nil
        }
        do {
            let config = MLModelConfiguration()
            let mlModel = try MLModel(contentsOf: url, configuration: config)
            return try VNCoreMLModel(for: mlModel)
        } catch {
            print("⚠️ [FoodClassifierService] Gagal load model: \(error)")
            return nil
        }
    }

    func classify(image: UIImage) async throws -> FoodPrediction {
        guard let vnModel else { throw FoodScanError.modelNotFound }
        guard let cgImage = image.cgImage else { throw FoodScanError.invalidImage }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: vnModel) { request, error in
                if let error {
                    continuation.resume(throwing: FoodScanError.classificationFailed(error.localizedDescription))
                    return
                }
                guard let results = request.results as? [VNClassificationObservation],
                      let best = results.first else {
                    continuation.resume(throwing: FoodScanError.classificationFailed("No result"))
                    return
                }
                let prediction = FoodPrediction(
                    rawLabel: best.identifier,
                    confidence: Double(best.confidence)
                )
                continuation.resume(returning: prediction)
            }
            // Vision otomatis me-resize gambar sesuai input model (299x299).
            request.imageCropAndScaleOption = .centerCrop

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: FoodScanError.classificationFailed(error.localizedDescription))
            }
        }
    }
}

/// Classifier tiruan untuk:
///  - menjalankan app saat model .mlmodel belum di-download (mode demo)
///  - unit testing yang deterministik
final class MockFoodClassifier: FoodClassifying {
    /// Label yang akan dikembalikan; default acak dari database.
    var stubbedLabel: String?
    var stubbedConfidence: Double = 0.87

    init(stubbedLabel: String? = nil) {
        self.stubbedLabel = stubbedLabel
    }

    func classify(image: UIImage) async throws -> FoodPrediction {
        let label = stubbedLabel ?? CalorieDatabase.allLabels.randomElement() ?? "pizza"
        // Simulasi sedikit delay seperti inferensi nyata.
        try? await Task.sleep(nanoseconds: 300_000_000)
        return FoodPrediction(rawLabel: label, confidence: stubbedConfidence)
    }
}
