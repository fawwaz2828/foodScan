//
//  FoodGateService.swift
//  foodScan
//
//  Gerbang on-device murah: cek apakah foto memang MAKANAN sebelum dikirim ke
//  ChatGPT VLM. Tujuannya hemat biaya API — foto non-makanan ditolak lebih dulu.
//
//  Memakai model Create ML "FoodGate.mlmodel" (image classifier 2 kelas:
//  `food` / `non_food`, output `classLabel` + `classLabelProbs`). Dimuat
//  dinamis dari bundle agar app tetap jalan walau model belum tersedia.
//

import CoreML
import Vision
import UIKit

final class FoodGateService {

    static let shared = FoodGateService()

    /// Hasil evaluasi gate.
    struct Verdict {
        let isFood: Bool
        let confidence: Double   // 0.0–1.0 untuk label terpilih
    }

    /// Nama resource model (tanpa ekstensi). Setelah build menjadi `.mlmodelc`.
    private let modelResourceName = "FoodGate"

    private lazy var vnModel: VNCoreMLModel? = loadModel()

    private func loadModel() -> VNCoreMLModel? {
        guard let url = Bundle.main.url(forResource: modelResourceName, withExtension: "mlmodelc") else {
            print("⚠️ [FoodGateService] \(modelResourceName).mlmodelc tidak ditemukan — gate dilewati.")
            return nil
        }
        do {
            let mlModel = try MLModel(contentsOf: url, configuration: MLModelConfiguration())
            return try VNCoreMLModel(for: mlModel)
        } catch {
            print("⚠️ [FoodGateService] Gagal load model: \(error)")
            return nil
        }
    }

    /// Evaluasi sebuah gambar. Mengembalikan `nil` bila model tak tersedia atau
    /// inferensi gagal — pemanggil sebaiknya menganggapnya LOLOS (jangan blokir).
    func evaluate(image: UIImage) async -> Verdict? {
        guard let vnModel, let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: vnModel) { request, _ in
                guard let results = request.results as? [VNClassificationObservation],
                      let best = results.first else {
                    continuation.resume(returning: nil)
                    return
                }
                // Label model: "food" / "non_food". Apa pun selain "food" = bukan makanan.
                let id = best.identifier.lowercased()
                let isFood = id.contains("food") && !id.contains("non")
                #if DEBUG
                print("🍽️ [FoodGate] \(best.identifier) \(String(format: "%.2f", best.confidence)) | all: \(results.map { "\($0.identifier):\(String(format: "%.2f", $0.confidence))" })")
                #endif
                continuation.resume(returning: Verdict(isFood: isFood,
                                                       confidence: Double(best.confidence)))
            }
            request.imageCropAndScaleOption = .scaleFill
            // Teruskan orientasi foto agar gambar dari kamera tidak "miring".
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do { try handler.perform([request]) }
            catch { continuation.resume(returning: nil) }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ ui: UIImage.Orientation) {
        switch ui {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
