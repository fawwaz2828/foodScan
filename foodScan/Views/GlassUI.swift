//
//  GlassUI.swift
//  foodScan
//
//  Design system terang (light) bertema PUTIH + MERAH.
//  Kartu putih ber-shadow lembut di atas latar abu sangat muda, dengan
//  aksen merah brand untuk elemen fokus (tombol utama, ring, ikon kunci).
//
//  Komponen utama (nama dipertahankan agar layar lama tetap kompatibel):
//   - Color.brand / token warna  : palet terpusat
//   - AppBackground              : latar abu muda
//   - .cardStyle() / .glassCard(): kartu putih ber-shadow
//   - GlassButtonStyle           : tombol (merah solid untuk aksi utama)
//   - AppearanceConfigurator     : nav bar bersih untuk tema terang
//

import SwiftUI

// MARK: - Palet warna brand (putih + merah)

extension Color {
    /// Aksen merah utama FoodScan (tema putih + merah).
    static let brand = Color(red: 0.86, green: 0.16, blue: 0.20)
    /// Merah lembut (pink muda) untuk latar/chip sekunder.
    static let brandSoft = Color(red: 0.99, green: 0.91, blue: 0.92)
    /// Latar layar — putih keabuan sangat muda.
    static let appBackground = Color(red: 0.98, green: 0.97, blue: 0.97)
    /// Permukaan kartu.
    static let cardBackground = Color.white
    /// Teks utama (hampir hitam).
    static let primaryText = Color(red: 0.11, green: 0.12, blue: 0.18)
    /// Teks sekunder (abu).
    static let secondaryText = Color(red: 0.55, green: 0.56, blue: 0.60)

    // Warna macro (sesuai mockup Food Details).
    static let macroCarbs = Color(red: 0.96, green: 0.55, blue: 0.22)   // oranye
    static let macroFat = Color(red: 0.27, green: 0.60, blue: 0.96)     // biru
    static let macroProtein = Color(red: 0.30, green: 0.78, blue: 0.45) // hijau

    /// Gradien aksen merah untuk tombol/ring utama.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.91, green: 0.22, blue: 0.27),
                                Color(red: 0.78, green: 0.12, blue: 0.18)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Latar belakang aplikasi

/// Latar terang netral agar kartu putih & aksen merah menonjol.
struct AppBackground: View {
    var body: some View {
        Color.appBackground.ignoresSafeArea()
    }
}

// MARK: - Kartu putih

private struct CardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var padding: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 18)
            .background(Color.cardBackground,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

extension View {
    /// Membungkus konten menjadi kartu putih ber-shadow lembut.
    func cardStyle(cornerRadius: CGFloat = 24, padding: CGFloat? = nil) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    /// Alias kompatibilitas untuk layar yang masih memanggil `.glassCard(...)`.
    func glassCard(cornerRadius: CGFloat = 24, padding: CGFloat? = nil) -> some View {
        cardStyle(cornerRadius: cornerRadius, padding: padding)
    }

    /// Membatasi lebar konten utama agar tidak meregang terlalu lebar di layar
    /// besar (iPad/landscape), lalu memusatkannya. Di iPhone potret (lebar <
    /// maxWidth) tidak berdampak — konten tetap mengisi seperti biasa.
    func appContentWidth(_ maxWidth: CGFloat = 480) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Gaya tombol

struct GlassButtonStyle: ButtonStyle {
    /// `true` = tombol aksi utama (merah solid, teks putih).
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(prominent ? Color.white : Color.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background {
                if prominent {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.brand, Color.brand.opacity(0.85)],
                                startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: Color.brand.opacity(0.35), radius: 12, x: 0, y: 6)
                } else {
                    Capsule(style: .continuous)
                        .fill(Color.cardBackground)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Konfigurasi chrome global (nav bar)

/// Nav bar bersih dengan judul gelap, cocok untuk tema terang.
enum AppearanceConfigurator {
    static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor.label]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}
