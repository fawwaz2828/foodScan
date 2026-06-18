//
//  Haptics.swift
//  foodScan
//
//  UI Intelligence: memetakan health_score (dari NutritionFactAgent) ke
//  kategori → haptic feedback, warna overlay, dan saran singkat.
//
//  Catatan tema: app bertema monokrom, tetapi warna overlay sehat/borderline/
//  tidak-sehat memang disyaratkan semantik (hijau/oranye/merah transparan)
//  sebagai pengecualian fungsional.
//

import SwiftUI
import UIKit

enum HealthCategory {
    case healthy     // score >= 7
    case borderline  // 4.0 – 6.9
    case unhealthy   // 0 – 3.9

    init(score: Double) {
        switch score {
        case 7...:      self = .healthy
        case 4..<7:     self = .borderline
        default:        self = .unhealthy
        }
    }

    /// Warna overlay transparan (latar lembut) untuk kartu hasil.
    var overlayColor: Color {
        switch self {
        case .healthy:    return Color.green.opacity(0.12)
        case .borderline: return Color.orange.opacity(0.12)
        case .unhealthy:  return Color.red.opacity(0.12)
        }
    }

    /// Warna aksen solid (ikon/teks) sesuai kategori.
    var tint: Color {
        switch self {
        case .healthy:    return Color(red: 0.18, green: 0.55, blue: 0.28)
        case .borderline: return Color(red: 0.80, green: 0.52, blue: 0.10)
        case .unhealthy:  return Color.brand
        }
    }

    var icon: String {
        switch self {
        case .healthy:    return "checkmark.seal.fill"
        case .borderline: return "exclamationmark.circle.fill"
        case .unhealthy:  return "xmark.octagon.fill"
        }
    }

    var title: String {
        switch self {
        case .healthy:    return "Pilihan Sehat"
        case .borderline: return "Cukup, Tapi Hati-hati"
        case .unhealthy:  return "Kurang Sehat"
        }
    }

    /// Saran singkat sesuai kategori (ditampilkan di kartu).
    var advice: String {
        switch self {
        case .healthy:    return "Bagus! Pertahankan pilihan seperti ini."
        case .borderline: return "Boleh, tapi imbangi dengan sayur & air putih."
        case .unhealthy:  return "Sesekali tak apa — kurangi porsi atau frekuensinya."
        }
    }
}

/// Pemicu haptic sesuai kategori kesehatan.
@MainActor
enum Haptics {
    static func play(for category: HealthCategory) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch category {
        case .healthy:    style = .light    // ringan
        case .borderline: style = .medium   // sedang
        case .unhealthy:  style = .heavy    // berat
        }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}
