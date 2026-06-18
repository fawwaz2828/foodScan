# FoodScan — Arsitektur SwiftUI Multi-Agent

Aplikasi iOS untuk mendeteksi makanan & estimasi gizi dari foto. Jalur analisis
**utama** memakai **VLM ChatGPT (OpenAI Vision)**; ada **gerbang Core ML
on-device** (food / non-food) untuk hemat biaya, dan jalur **fallback Core ML**
klasik bila API key tidak tersedia. Dibangun dengan **SwiftUI** + arsitektur
**multi-agent**.

| Item | Nilai |
|------|-------|
| UI | SwiftUI (MVVM) |
| Concurrency | Swift `async/await`, `actor` |
| AI utama | OpenAI ChatGPT — `gpt-4o` (vision), `gpt-4o-mini` (teks), JSON mode |
| On-device ML | Core ML + Vision (FoodGate; fallback classifier) |
| Persistensi | File JSON lokal + UserDefaults |

---

## 1. Struktur Folder (Module Design)

```
foodScan/
├─ foodScanApp.swift          # Entry point + AppContainer (composition root)
├─ ContentView.swift          # Root tab bar (Home / Stats / Scan / History / Menu)
├─ Models/
│   ├─ FoodModels.swift       # FoodPrediction, CalorieEstimate, ScanRecord, DailyRecommendation
│   ├─ AIModels.swift         # NutritionalInfo, FoodIngredient, VisionFoodAnalysis, GeneratedRecipe, …
│   └─ Profile.swift          # Sex/Activity/Goal/MealTime + GoalCalculator
├─ Agents/                    # ◀ INTI: 7 AI Agent
│   ├─ Agent.swift                       # protocol Agent + AgentEventDelegate + diagram alur
│   ├─ AgentCoordinator.swift            # Orkestrator (pipeline / chain-of-responsibility)
│   ├─ ImageRecognitionAgent.swift       # Agent 1  (Core ML)
│   ├─ CalorieEstimationAgent.swift      # Agent 2
│   ├─ PersistenceAgent.swift            # Agent 3
│   ├─ RecommendationAgent.swift         # Agent 4
│   ├─ NutritionFactAgent.swift          # Agent 5  (ChatGPT)
│   ├─ EnhancedRecommendationAgent.swift # Agent 6  (ChatGPT, RAG 7 hari)
│   └─ VisionFoodAnalysisAgent.swift     # Agent 7  (VLM ChatGPT) — jalur utama
├─ Services/                  # Tools/infrastruktur yang DIPAKAI agent
│   ├─ OpenAIVisionService.swift   # Klien ChatGPT (vision+teks, JSON, rate-limit, retry)
│   ├─ OpenAIVisionPrompts.swift   # System prompt tiap panggilan AI
│   ├─ FoodGateService.swift       # Gerbang Core ML "food / non_food"
│   ├─ FoodClassifierService.swift # Classifier Core ML (jalur fallback) + Mock
│   ├─ CalorieDatabase.swift       # Knowledge base label → kalori
│   ├─ PersistenceService.swift    # HistoryStoring (JSON file / in-memory)
│   └─ UserSettings.swift          # Profil, target, API key, "Reduce AI usage"
├─ ViewModels/
│   ├─ ScanViewModel.swift         # scan + enrichment + chat + recipe
│   └─ HistoryViewModel.swift      # riwayat, rekomendasi harian, manual log
├─ Views/                     # Home, Scan, ScanResult, History, Statistic,
│                             # Menu, Onboarding, ManualLog, WeightTracking, AICards
├─ Utilities/                 # ImagePicker, Haptics, SpeechTranscriber, ImageStore
└─ FoodGate.mlmodel           # ◀ Model Core ML gerbang makanan

foodScanTests/foodScanTests.swift   # Unit test tiap Agent + pipeline
```

**Prinsip desain**: MVVM · Single Responsibility per agent · protocol + DI
(`FoodClassifying`, `HistoryStoring`) agar mudah di-mock · pemisahan tegas
**Agent** (unit penalaran) vs **Service/Tool** (klien jaringan/ML).

---

## 2. Daftar Agent — Peran, Skill, I/O, Ticket

Semua agent meng-implementasi protocol `Agent` (identitas + peran + skill + satu
operasi `perform`):

```swift
protocol Agent {
    associatedtype Input
    associatedtype Output
    var name: String { get }
    var role: String { get }
    var skills: [String] { get }
    func perform(_ input: Input) async throws -> Output
}
```

| # | Agent | Peran | Skill utama | Input → Output | Ticket |
|---|-------|-------|-------------|----------------|--------|
| 1 | **ImageRecognitionAgent** | Kenali jenis makanan dari gambar (Core ML) | Load `.mlmodelc` dinamis; preprocessing Vision; pilih confidence tertinggi | `UIImage` → `FoodPrediction` | #A1 |
| 2 | **CalorieEstimationAgent** | Konversi label → kalori | Lookup `CalorieDatabase`; fallback default; teruskan confidence | `FoodPrediction` → `CalorieEstimate` | #A2 |
| 3 | **PersistenceAgent** | Simpan & kelola riwayat | CRUD `ScanRecord`; sumber data Agent 4 & 6 | `Estimate/Record` → `ScanRecord` | #A3 |
| 4 | **RecommendationAgent** | Saran & notifikasi kalori harian | Agregasi harian; banding target; pesan; notifikasi lokal | `[ScanRecord]` → `DailyRecommendation` | #A4 |
| 5 | **NutritionFactAgent** | Perkaya gizi + skor sehat | ChatGPT: protein/karbo/lemak/serat; health_score 1–10; map ke HealthCategory | `NutritionInput` → `NutritionalInfo` | #A5 |
| 6 | **EnhancedRecommendationAgent** | Saran personal + What-If (RAG) | Baca riwayat 7 hari; saran berpola; 2 swap; reminder malam | `[ScanRecord]` → `PersonalAdvice` / `[WhatIfAlternative]` | #A6 |
| 7 | **VisionFoodAnalysisAgent** | Analisis foto ujung-ke-ujung (VLM) | Kirim gambar ke OpenAI Vision; decode JSON; **deteksi setiap bahan** | `UIImage` → `VisionFoodAnalysis` | #A7 |

**Tools bersama (bukan Agent):**

| Tool | Tanggung jawab |
|------|----------------|
| **OpenAIService** | Klien ChatGPT tunggal (`actor`): vision + 7 endpoint teks, JSON mode, rate-limit, retry 429/5xx. Dipakai Agent 5/6/7 & fitur chat/recipe. |
| **FoodGateService** | Classifier Core ML on-device (`food`/`non_food`) dijalankan **sebelum** memanggil API — menolak foto non-makanan agar hemat biaya. |

---

## 3. Kolaborasi Antar-Agent

Agent **tidak saling memanggil langsung**. Orkestrasi oleh `AgentCoordinator`
(pola **pipeline / chain-of-responsibility**); progres tiap tahap dilaporkan ke
UI lewat **delegate** `AgentEventDelegate`:

```swift
protocol AgentEventDelegate: AnyObject {
    func agentDidStart(stage: AgentStage)
    func agentDidFinish(stage: AgentStage, detail: String)
    func agentDidFail(stage: AgentStage, error: Error)
}
```

### Alur utama (VLM) — `AgentCoordinator.runWithVision`

```
User → ScanViewModel.scan()
  │
  ├─▶ FoodGateService (Core ML)  ── bukan makanan? ──▶ tolak (tanpa panggilan API)
  │
  ▼  makanan
  AgentCoordinator.runWithVision(image:)
    1. Agent 7  VisionFoodAnalysisAgent → VisionFoodAnalysis
                                          (nama, kalori, makro, skor, BAHAN)
    2. Agent 3  PersistenceAgent        → ScanRecord tersimpan (+ gizi)
    3. Agent 4  RecommendationAgent     → DailyRecommendation
  ▼
  ScanViewModel.enrich()   (proaktif; bisa dimatikan via "Reduce AI usage")
    • Agent 6  EnhancedRecommendationAgent → What-If (2 swap)
    • portion hint (OpenAIService)         → PortionHint
  ▼
  UI update (Scan result, Home, History)
```

### Alur fallback (tanpa API key) — `AgentCoordinator.run`

```
Agent 1 (Recognition) → Agent 2 (Estimation) → Agent 3 (Persistence)
  → Agent 5 (Nutrition) → Agent 4 (Recommendation)
```

---

## 4. Ticket / Workflow Documentation

Tiap agent dispesifikasikan sebagai user-story ticket (juga tertanam di header
file masing-masing agent).

| # | Agent | User Story (As / I want / So that) | Acceptance |
|---|-------|------------------------------------|------------|
| A1 | Recognition | Pipeline ingin gambar diklasifikasi jadi jenis makanan agar agent kalori tahu yang dihitung | confidence 0–1; error eksplisit bila model/gambar invalid |
| A2 | Estimation | Pipeline ingin kalori untuk makanan terkenali agar user lihat estimasi | label tak dikenal tetap dapat default wajar |
| A3 | Persistence | User ingin tiap scan tersimpan agar bisa lihat riwayat & total harian | data bertahan setelah app ditutup; bisa dihapus |
| A4 | Recommendation | User ingin tahu apakah kalori hari ini berlebih agar bisa menjaga pola | hanya record hari ini; pesan beda low/onTrack/high |
| A5 | Nutrition | User ingin makro & skor sehat agar bisa menilai kualitas, bukan cuma kalori | makro + skor 1–10 tampil; gagal diam-diam bila tanpa API key |
| A6 | EnhancedRecommendation | User ingin saran personal + simulasi "what-if" agar tahu langkah konkret | saran rujuk pola 7 hari nyata; What-If tepat 2 swap; reminder saat sisa < 500 |
| A7 | VisionFoodAnalysis | User ingin cukup memotret lalu dapat nama/kalori/gizi/**setiap bahan** agar log akurat tanpa mengetik | 1 panggilan VLM → `VisionFoodAnalysis` lengkap; non-makanan ditolak; hanya saat ada API key |
| C1 | Coordinator | Orkestrasi pipeline end-to-end | output A(n) jadi input A(n+1); progres dilaporkan via delegate |

---

## 5. Data Flow & Persistensi

- **Riwayat** (`ScanRecord`) disimpan sebagai **JSON lokal** via `FileHistoryStore`
  (tidak meninggalkan perangkat). Bisa diganti ke Core Data tanpa ubah Agent —
  cukup implementasi baru `HistoryStoring`.
- **Foto** dikirim ke OpenAI **hanya** saat scan/chat untuk analisis
  (disampaikan di onboarding & Help).
- **Profil/target/berat** di UserDefaults (`UserSettings`, `WeightStore`).
- **API key** dibaca saat request: Settings → env `OPENAI_API_KEY` → fallback.

---

## 6. Model Core ML

- **`FoodGate.mlmodel`** — image classifier 2 kelas (`food` / `non_food`,
  output `classLabel` + `classLabelProbs`). Dijalankan on-device sebagai gerbang
  sebelum panggilan API. Dimuat dinamis (`MLModel(contentsOf:)` + Vision),
  konservatif (hanya blokir bila confidence ≥ 0.95).
- **FoodClassifierService** (jalur fallback) memuat classifier secara dinamis;
  bila model tidak ada → `MockFoodClassifier` (mode demo). Catatan: model lama
  `SeeFood.mlmodel` telah dihapus karena VLM ChatGPT menggantikan klasifikasi.

---

## 7. Testing

`foodScanTests/foodScanTests.swift` memuat unit test tiap Agent + integrasi
pipeline, memakai `MockFoodClassifier` & `InMemoryHistoryStore` (deterministik).
Jalankan dengan **⌘U** di Xcode.

> Catatan: agent berbasis ChatGPT (5/6/7) diuji lewat parsing JSON
> (decode `NutritionalInfo`/`VisionFoodAnalysis`) agar tidak bergantung jaringan.

---

## 8. Catatan Build

- `GENERATE_INFOPLIST_FILE = YES`; usage description diset via build settings:
  kamera, mikrofon, galeri, speech, **dan HealthKit** (share/update) untuk fitur
  Apple Health (capability HealthKit perlu diaktifkan di Xcode → Signing &
  Capabilities).
- Kamera hanya berfungsi di perangkat fisik (Simulator fallback ke galeri).
- Tempel API key OpenAI di **Settings → AI** (atau env `OPENAI_API_KEY`).
