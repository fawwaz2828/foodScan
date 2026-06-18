//
//  ImageRecognitionAgent.swift
//  foodScan
//
//  ╔══════════════════════════════════════════════════════════════════════╗
//  ║ AGENT 1 — IMAGE RECOGNITION AGENT                                      ║
//  ╠══════════════════════════════════════════════════════════════════════╣
//  ║ PERAN : Mengubah gambar makanan menjadi label kelas + confidence.     ║
//  ║ SKILL : - Memuat & menjalankan model Core ML (Food101, InceptionV3)   ║
//  ║         - Preprocessing gambar (resize/crop via Vision)               ║
//  ║         - Memilih prediksi dengan confidence tertinggi                ║
//  ║ INPUT : UIImage                                                        ║
//  ║ OUTPUT: FoodPrediction (rawLabel, confidence)                         ║
//  ║ KOLAB : Output diteruskan Coordinator ke CalorieEstimationAgent.      ║
//  ║         Jika model belum ada, Agent melempar .modelNotFound sehingga  ║
//  ║         Coordinator bisa beralih ke MockFoodClassifier (mode demo).   ║
//  ╚══════════════════════════════════════════════════════════════════════╝
//
//  TICKET #A1
//   - As: pipeline
//   - I want: gambar diklasifikasikan menjadi jenis makanan
//   - So that: Agent kalori tahu makanan apa yang dihitung
//   - Acceptance: confidence di-normalisasi 0..1; error eksplisit bila model
//     tidak tersedia atau gambar invalid.
//

import UIKit

final class ImageRecognitionAgent: Agent {
    let name = "ImageRecognitionAgent"
    let role = "Mengenali jenis makanan dari gambar menggunakan Core ML."
    let skills = [
        "Load model Core ML (.mlmodelc) secara dinamis",
        "Preprocessing gambar via Vision (resize 299x299, center-crop)",
        "Inferensi & seleksi prediksi confidence tertinggi"
    ]

    private let classifier: FoodClassifying

    /// Dependency injection: production memakai `FoodClassifierService`,
    /// test/demo memakai `MockFoodClassifier`.
    init(classifier: FoodClassifying) {
        self.classifier = classifier
    }

    func perform(_ input: UIImage) async throws -> FoodPrediction {
        try await classifier.classify(image: input)
    }
}
