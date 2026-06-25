//
//  OpenAIVisionService.swift
//  foodScan
//
//  Klien TUNGGAL untuk semua fitur AI aplikasi, memakai ChatGPT (OpenAI):
//   - Vision: analisis FOTO makanan → nama, kalori, gizi, dan SETIAP BAHAN.
//   - Teks  : gizi, rekomendasi 7 hari, what-if, koreksi suara, portion hint,
//             food chat, estimasi makanan manual.
//
//  Menggantikan GroqService sepenuhnya. Diimplementasikan sebagai `actor`
//  (aman dari data race), memakai JSON mode + rate limiting + retry pada 429/5xx.
//
//  API KEY: env OPENAI_API_KEY; bila kosong, pakai konstanta `fallbackKey`
//  di bawah — TEMPEL API KEY ChatGPT kamu di sana.
//

import UIKit

enum OpenAIError: LocalizedError {
    case missingAPIKey
    case invalidImage
    case http(Int, String)
    case decoding(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "OPENAI_API_KEY isn't set. Add your ChatGPT API key in Secrets.swift."
        case .invalidImage: return "The image couldn't be processed."
        case .http(let code, let msg): return "OpenAI HTTP \(code): \(msg)"
        case .decoding(let d): return "Couldn't parse the OpenAI response: \(d)"
        case .empty: return "The OpenAI response was empty."
        }
    }
}

actor OpenAIService {

    /// Instance bersama untuk seluruh agent & view model.
    static let shared = OpenAIService()

    /// Key diambil dari `Secrets.swift` (file lokal yang TIDAK ikut ke Git),
    /// atau dari environment variable OPENAI_API_KEY. Tempel key di Secrets.swift.
    private static let fallbackKey = Secrets.apiKey

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    /// Model vision-capable (mendukung gambar + JSON mode).
    private let visionModel: String
    /// Model untuk tugas teks (lebih murah/cepat).
    private let textModel: String
    private let apiKeyOverride: String?
    private let session: URLSession

    // Rate limiting: jarak minimum antar-request (serial via actor).
    private let minInterval: TimeInterval = 0.5
    private var lastRequestAt = Date.distantPast

    init(visionModel: String = "gpt-4o-mini",
         textModel: String = "gpt-4o-mini",
         apiKey: String? = nil,
         session: URLSession = .shared) {
        self.visionModel = visionModel
        self.textModel = textModel
        self.apiKeyOverride = apiKey
        self.session = session
    }

    /// Key efektif: prioritas override init → input pengguna di Settings →
    /// environment → konstanta bawaan.
    private var apiKey: String {
        if let apiKeyOverride, !apiKeyOverride.isEmpty { return apiKeyOverride }
        let stored = UserDefaults.standard.string(forKey: UserSettings.SharedKeys.openAIKey) ?? ""
        if !stored.isEmpty { return stored }
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty { return env }
        return Self.fallbackKey
    }

    /// `true` bila API key sudah diset (menentukan apakah jalur AI dipakai).
    var isConfigured: Bool { !apiKey.isEmpty }

    // MARK: - Vision

    /// Analisis satu foto makanan → gizi lengkap + setiap bahan yang terdeteksi.
    func analyzeFood(image: UIImage) async throws -> VisionFoodAnalysis {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }
        guard let dataURL = Self.jpegDataURL(from: image) else { throw OpenAIError.invalidImage }

        let parts: [ContentPart] = [
            .text("Carefully analyze the food in this photo. Identify EVERY visible ingredient/component, then reply with ONLY JSON matching the schema."),
            .imageURL(dataURL, detail: "high")
        ]
        let content = try await complete(model: visionModel,
                                         system: OpenAIPrompts.foodAnalysis,
                                         userParts: parts, temperature: 0.2)
        return try decode(VisionFoodAnalysis.self, from: content)
    }

    // MARK: - Teks (port dari GroqService)

    /// 1) Rincian gizi + skor kesehatan untuk satu makanan.
    func requestNutrition(foodName: String, calories: Int, portionRatio: Double) async throws -> NutritionalInfo {
        let user = """
        Analyze the nutrition of the following food and reply with JSON.
        - Food name: \(foodName)
        - Estimated calories (detected portion): \(calories) kcal
        - Portion ratio: \(portionRatio)
        """
        let content = try await completeText(system: OpenAIPrompts.nutrition, user: user, temperature: 0.3)
        return try decode(NutritionalInfo.self, from: content)
    }

    /// 2) Saran personal berbasis riwayat 7 hari (+ simulasi opsional).
    func requestRecommendation(history: [ScanRecord], dailyTarget: Int) async throws -> PersonalAdvice {
        let lines = history
            .map { "- \($0.displayName): \($0.calories) kcal (\(Self.dateFmt.string(from: $0.date)))" }
            .joined(separator: "\n")
        let user = """
        Daily calorie target: \(dailyTarget) kcal.
        Last 7 days of meals:
        \(lines.isEmpty ? "(no data yet)" : lines)

        Give personalized advice + one short 'what if' simulation. Reply with JSON.
        """
        let content = try await completeText(system: OpenAIPrompts.recommendation, user: user, temperature: 0.6)
        return try decode(PersonalAdvice.self, from: content)
    }

    /// 3) Koreksi berdasarkan transkrip suara pengguna.
    func requestVoiceCorrection(transcript: String, currentFood: String, currentCalories: Int) async throws -> VoiceCorrectionResult {
        let user = """
        Current food: \(currentFood) (\(currentCalories) kcal).
        User's spoken input: "\(transcript)"
        Interpret the user's correction and reply with JSON.
        """
        let content = try await completeText(system: OpenAIPrompts.voiceCorrection, user: user, temperature: 0.2)
        return try decode(VoiceCorrectionResult.self, from: content)
    }

    /// 4) Perkiraan porsi memakai objek referensi di samping makanan.
    func requestPortionHint(foodName: String, referenceObject: String, baseCalories: Int) async throws -> PortionHint {
        let user = """
        Detected food: \(foodName) (standard calories for 1 serving: \(baseCalories) kcal).
        Reference object in the photo: \(referenceObject).
        Estimate the portion size relative to 1 standard serving. Reply with JSON.
        """
        let content = try await completeText(system: OpenAIPrompts.portionHint, user: user, temperature: 0.2)
        return try decode(PortionHint.self, from: content)
    }

    /// 5) Simulasi What-If proaktif: alternatif tukar makanan hemat kalori.
    func requestWhatIf(lastScannedFood: String, todayTotal: Int, dailyGoal: Int,
                       remainingCalories: Int, last3Meals: [String]) async throws -> [WhatIfAlternative] {
        let user = """
        Last food: \(lastScannedFood).
        Today's total calories: \(todayTotal) / target \(dailyGoal) (remaining \(remainingCalories)).
        Last 3 meals: \(last3Meals.isEmpty ? "-" : last3Meals.joined(separator: ", ")).
        Give exactly 2 healthier/lower-calorie swap alternatives. Reply with JSON.
        """
        let content = try await completeText(system: OpenAIPrompts.whatIf, user: user, temperature: 0.5)
        return try decode(WhatIfWrapper.self, from: content).alternatives
    }

    /// 6) Tanya-jawab makanan yang baru dipindai.
    func requestFoodChat(foodName: String, calories: Int, portion: Double?,
                         nutrition: NutritionalInfo?, userQuestion: String) async throws -> String {
        let portionText = portion.map { String(format: "%.1fx", $0) } ?? "not available"
        let nutritionText: String
        if let nutrition {
            nutritionText = """
            - Protein: \(Int(nutrition.proteinGram)) g
            - Carbs: \(Int(nutrition.carbsGram)) g
            - Fat: \(Int(nutrition.fatGram)) g
            - Fiber: \(Int(nutrition.fiberGram)) g
            - Health score: \(String(format: "%.1f", nutrition.healthScore))/10
            """
        } else {
            nutritionText = "- Detailed nutrition data isn't available."
        }

        let user = """
        Food context:
        - Food name: \(foodName)
        - Estimated calories: \(calories) kcal
        - Estimated portion: \(portionText)
        \(nutritionText)

        User's question:
        \(userQuestion)
        """
        let content = try await completeText(system: OpenAIPrompts.foodChat, user: user, temperature: 0.4)
        return try decode(FoodChatAnswer.self, from: content).answer
    }

    /// 7) Estimasi gizi dari teks bebas (log makanan tanpa foto).
    func requestManualEstimate(description: String) async throws -> ManualFoodEstimate {
        let user = """
        Food typed by the user: "\(description)"
        Estimate a clean name, total calories, nutrition, and every ingredient. Reply with JSON.
        """
        let content = try await completeText(system: OpenAIPrompts.manualEstimate, user: user, temperature: 0.3)
        return try decode(ManualFoodEstimate.self, from: content)
    }

    /// 8) Generate resep untuk memasak ulang makanan hasil scan.
    func requestRecipe(foodName: String, calories: Int, ingredients: [FoodIngredient]?) async throws -> GeneratedRecipe {
        let detected: String
        if let ingredients, !ingredients.isEmpty {
            detected = ingredients.map { "- \($0.name) (~\(Int($0.estimatedGrams)) g)" }.joined(separator: "\n")
        } else {
            detected = "(no ingredient details yet)"
        }
        let user = """
        Food: \(foodName) (~\(calories) kcal per detected portion).
        Ingredients detected from the photo:
        \(detected)

        Create a recipe to cook this food. Reply with JSON.
        """
        let content = try await completeText(system: OpenAIPrompts.recipe, user: user, temperature: 0.5)
        return try decode(GeneratedRecipe.self, from: content)
    }

    // MARK: - Inti pemanggilan + rate limiting

    private func waitForSlot() async {
        let since = Date().timeIntervalSince(lastRequestAt)
        if since < minInterval {
            try? await Task.sleep(nanoseconds: UInt64((minInterval - since) * 1_000_000_000))
        }
        lastRequestAt = Date()
    }

    /// Panggilan teks (JSON mode) memakai `textModel`.
    private func completeText(system: String, user: String, temperature: Double) async throws -> String {
        try await complete(model: textModel, system: system, userParts: [.text(user)], temperature: temperature)
    }

    /// Satu panggilan chat completion (JSON mode) dengan retry pada 429/5xx.
    private func complete(model: String, system: String, userParts: [ContentPart], temperature: Double) async throws -> String {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        var attempt = 0
        while true {
            await waitForSlot()

            let payload = ChatRequest(
                model: model,
                temperature: temperature,
                responseFormat: .init(type: "json_object"),
                messages: [
                    .init(role: "system", content: [.text(system)]),
                    .init(role: "user", content: userParts)
                ]
            )
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(payload)

            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0

            if (code == 429 || code >= 500) && attempt < 3 {
                attempt += 1
                let backoff = pow(2.0, Double(attempt)) * 0.5
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                continue
            }
            guard (200..<300).contains(code) else {
                throw OpenAIError.http(code, String(data: data, encoding: .utf8) ?? "")
            }
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
                throw OpenAIError.empty
            }
            return content
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from content: String) throws -> T {
        guard let data = content.data(using: .utf8) else { throw OpenAIError.decoding("utf8") }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        do { return try dec.decode(T.self, from: data) }
        catch { throw OpenAIError.decoding("\(error.localizedDescription) | raw: \(content)") }
    }

    /// Kompres gambar ke JPEG dan bungkus jadi data URL base64 (≤ ~1024px agar hemat token).
    private static func jpegDataURL(from image: UIImage) -> String? {
        let resized = image.resizedForVision(maxDimension: 1024)
        guard let data = resized.jpegData(compressionQuality: 0.7) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE dd/MM"; f.locale = Locale(identifier: "en_US"); return f
    }()
}

// MARK: - DTO transport (request/response Chat Completions)

/// Bagian konten multimodal: teks atau gambar.
private enum ContentPart: Encodable {
    case text(String)
    case imageURL(String, detail: String)

    enum CodingKeys: String, CodingKey { case type, text, imageURL = "image_url" }
    struct ImagePayload: Encodable { let url: String; let detail: String }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try c.encode("text", forKey: .type)
            try c.encode(t, forKey: .text)
        case .imageURL(let url, let detail):
            try c.encode("image_url", forKey: .type)
            try c.encode(ImagePayload(url: url, detail: detail), forKey: .imageURL)
        }
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let temperature: Double
    let responseFormat: ResponseFormat
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, temperature, messages
        case responseFormat = "response_format"
    }
    struct ResponseFormat: Encodable { let type: String }
    struct Message: Encodable { let role: String; let content: [ContentPart] }
}

private struct ChatResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable { let message: Message }
    struct Message: Decodable { let content: String }
}

/// Pembungkus karena JSON mode harus berupa objek (bukan array di root).
private struct WhatIfWrapper: Decodable { let alternatives: [WhatIfAlternative] }
private struct FoodChatAnswer: Decodable { let answer: String }

// MARK: - Util resize gambar

private extension UIImage {
    /// Mengecilkan sisi terpanjang ke `maxDimension` (jaga rasio) demi efisiensi token.
    func resizedForVision(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
