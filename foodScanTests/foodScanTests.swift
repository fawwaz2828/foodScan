//
//  foodScanTests.swift
//  foodScanTests
//
//  Unit test untuk tiap Agent + pipeline Coordinator.
//  Menggunakan MockFoodClassifier & InMemoryHistoryStore agar deterministik
//  dan tidak menyentuh model nyata / disk.
//

import XCTest
@testable import foodScan

final class foodScanTests: XCTestCase {

    // MARK: - Agent 1: Image Recognition

    func testImageRecognitionAgentReturnsStubbedLabel() async throws {
        let classifier = MockFoodClassifier(stubbedLabel: "pizza")
        classifier.stubbedConfidence = 0.9
        let agent = ImageRecognitionAgent(classifier: classifier)

        let prediction = try await agent.perform(UIImage())

        XCTAssertEqual(prediction.rawLabel, "pizza")
        XCTAssertEqual(prediction.displayName, "Pizza")
        XCTAssertEqual(prediction.confidence, 0.9, accuracy: 0.001)
    }

    // MARK: - Agent 2: Calorie Estimation

    func testCalorieEstimationAgentMapsKnownLabel() async throws {
        let agent = CalorieEstimationAgent()
        let prediction = FoodPrediction(rawLabel: "hamburger", confidence: 0.8)

        let estimate = try await agent.perform(prediction)

        XCTAssertEqual(estimate.caloriesPerServing, CalorieDatabase.calories(for: "hamburger"))
        XCTAssertEqual(estimate.displayName, "Hamburger")
    }

    func testCalorieEstimationAgentFallsBackForUnknownLabel() async throws {
        let agent = CalorieEstimationAgent()
        let prediction = FoodPrediction(rawLabel: "tidak_ada_di_db", confidence: 0.5)

        let estimate = try await agent.perform(prediction)

        XCTAssertEqual(estimate.caloriesPerServing, CalorieDatabase.defaultCalories)
    }

    // MARK: - Agent 3: Persistence

    func testPersistenceAgentSavesRecord() async throws {
        let store = InMemoryHistoryStore()
        let agent = PersistenceAgent(store: store)
        let estimate = CalorieEstimate(foodLabel: "sushi", displayName: "Sushi",
                                       caloriesPerServing: 300, confidence: 0.7)

        let record = try await agent.perform(PersistenceInput(estimate: estimate, imageFileName: nil))

        XCTAssertEqual(agent.allRecords().count, 1)
        XCTAssertEqual(record.calories, 300)
        XCTAssertEqual(store.records.first?.foodLabel, "sushi")
    }

    func testPersistenceAgentDeletesRecord() async throws {
        let store = InMemoryHistoryStore()
        let agent = PersistenceAgent(store: store)
        let estimate = CalorieEstimate(foodLabel: "ramen", displayName: "Ramen",
                                       caloriesPerServing: 440, confidence: 0.6)
        let record = try await agent.perform(PersistenceInput(estimate: estimate, imageFileName: nil))

        try agent.delete(id: record.id)

        XCTAssertTrue(agent.allRecords().isEmpty)
    }

    // MARK: - Agent 4: Recommendation

    func testRecommendationAgentDetectsHighIntake() async throws {
        let agent = RecommendationAgent(dailyTarget: 1000)
        let records = [
            ScanRecord(foodLabel: "pizza", displayName: "Pizza", calories: 800, confidence: 0.9, date: Date()),
            ScanRecord(foodLabel: "nachos", displayName: "Nachos", calories: 600, confidence: 0.9, date: Date())
        ]

        let rec = try await agent.perform(records)

        XCTAssertEqual(rec.totalCaloriesToday, 1400)
        XCTAssertEqual(rec.status, .high)
    }

    func testRecommendationAgentIgnoresOtherDays() async throws {
        let agent = RecommendationAgent(dailyTarget: 2000)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let records = [
            ScanRecord(foodLabel: "pizza", displayName: "Pizza", calories: 900, confidence: 0.9, date: yesterday),
            ScanRecord(foodLabel: "sushi", displayName: "Sushi", calories: 300, confidence: 0.9, date: Date())
        ]

        let rec = try await agent.perform(records)

        XCTAssertEqual(rec.totalCaloriesToday, 300) // hanya hari ini
        XCTAssertEqual(rec.status, .low)
    }

    // MARK: - Integrasi: seluruh pipeline Coordinator

    func testCoordinatorRunsFullPipeline() async throws {
        let store = InMemoryHistoryStore()
        let coordinator = AgentCoordinator(
            recognitionAgent: ImageRecognitionAgent(classifier: MockFoodClassifier(stubbedLabel: "pizza")),
            estimationAgent: CalorieEstimationAgent(),
            persistenceAgent: PersistenceAgent(store: store),
            recommendationAgent: RecommendationAgent(dailyTarget: 2000)
        )

        let result = try await coordinator.run(image: UIImage())

        XCTAssertEqual(result.record.foodLabel, "pizza")
        XCTAssertEqual(result.record.calories, CalorieDatabase.calories(for: "pizza"))
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(result.recommendation.totalCaloriesToday, result.record.calories)
    }

    // MARK: - Helper: decode seperti OpenAIService (snake_case → camelCase)

    private func decodeAI<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Agent 7: Vision (parsing balasan VLM ChatGPT)

    func testVisionFoodAnalysisDecodesWithIngredients() throws {
        let json = """
        {
          "is_food": true,
          "name": "Nasi Goreng",
          "calories": 600,
          "protein_gram": 18,
          "carbs_gram": 80,
          "fat_gram": 22,
          "fiber_gram": 4,
          "health_score": 6,
          "confidence": 0.92,
          "insight": "Balanced but oily.",
          "ingredients": [
            { "name": "Rice", "estimated_grams": 200, "calories": 260 },
            { "name": "Egg",  "estimated_grams": 50,  "calories": 78 }
          ]
        }
        """
        let analysis = try decodeAI(VisionFoodAnalysis.self, json)

        XCTAssertTrue(analysis.isFood)
        XCTAssertEqual(analysis.name, "Nasi Goreng")
        XCTAssertEqual(analysis.calories, 600)
        XCTAssertEqual(analysis.proteinGram, 18, accuracy: 0.001)
        XCTAssertEqual(analysis.confidence, 0.92, accuracy: 0.001)
        XCTAssertEqual(analysis.ingredients.count, 2)
        XCTAssertEqual(analysis.ingredients.first?.name, "Rice")
        XCTAssertEqual(analysis.ingredients.first?.estimatedGrams, 200, accuracy: 0.001)
    }

    func testVisionAnalysisNutritionCarriesIngredients() throws {
        let json = """
        { "is_food": true, "name": "X", "calories": 100, "protein_gram": 1,
          "carbs_gram": 2, "fat_gram": 3, "fiber_gram": 0, "health_score": 5,
          "confidence": 0.5, "insight": "",
          "ingredients": [ { "name": "A", "estimated_grams": 10, "calories": 5 } ] }
        """
        let analysis = try decodeAI(VisionFoodAnalysis.self, json)
        // Konversi ke gizi internal harus membawa daftar bahan.
        XCTAssertEqual(analysis.nutrition.ingredients?.count, 1)
        XCTAssertEqual(analysis.nutrition.proteinGram, 1, accuracy: 0.001)
    }

    func testVisionRejectsNonFood() throws {
        let json = """
        { "is_food": false, "name": "", "calories": 0, "protein_gram": 0,
          "carbs_gram": 0, "fat_gram": 0, "fiber_gram": 0, "health_score": 0,
          "confidence": 0.1, "insight": "", "ingredients": [] }
        """
        let analysis = try decodeAI(VisionFoodAnalysis.self, json)
        XCTAssertFalse(analysis.isFood)
        XCTAssertTrue(analysis.ingredients.isEmpty)
    }

    // MARK: - Agent 5/manual: parsing estimasi gizi

    func testManualEstimateMapsToNutrition() throws {
        let json = """
        { "name": "Iced Tea", "calories": 90, "protein_gram": 0, "carbs_gram": 23,
          "fat_gram": 0, "fiber_gram": 0, "health_score": 4, "insight": "Sugary." }
        """
        let est = try decodeAI(ManualFoodEstimate.self, json)
        XCTAssertEqual(est.name, "Iced Tea")
        XCTAssertEqual(est.calories, 90)
        XCTAssertEqual(est.nutrition.carbsGram, 23, accuracy: 0.001)
        XCTAssertNil(est.nutrition.ingredients) // tidak wajib ada
    }

    func testNutritionalInfoDecodesWithoutIngredients() throws {
        let json = """
        { "protein_gram": 12, "carbs_gram": 30, "fat_gram": 8, "fiber_gram": 3,
          "health_score": 7, "insight": "Good." }
        """
        let info = try decodeAI(NutritionalInfo.self, json)
        XCTAssertEqual(info.healthScore, 7, accuracy: 0.001)
        XCTAssertNil(info.ingredients)
    }

    // MARK: - Meal time (edit entri + grouping)

    func testScanRecordMealTimeOverride() {
        let record = ScanRecord(foodLabel: "x", displayName: "X", calories: 100,
                                confidence: 1, mealTimeRaw: MealTime.dinner.rawValue)
        XCTAssertEqual(record.mealTime, .dinner)
    }

    func testScanRecordMealTimeDerivedFromDate() {
        let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
        let record = ScanRecord(foodLabel: "x", displayName: "X", calories: 100,
                                confidence: 1, date: morning)
        // Tanpa override → diturunkan dari jam (08:00 = breakfast).
        XCTAssertEqual(record.mealTime, .breakfast)
    }
}
