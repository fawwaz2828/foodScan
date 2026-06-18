//
//  StatisticView.swift
//  foodScan
//
//  Statistik bertema merah-putih: total kalori hari ini, grafik batang mingguan, dan
//  rata-rata gizi (Cal AI) dihitung dari riwayat scan nyata.
//

import SwiftUI

struct StatisticView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @EnvironmentObject private var settings: UserSettings

    private var target: Int { viewModel.recommendation?.dailyTarget ?? settings.dailyCalorieTarget }

    /// Hanya record yang sudah punya rincian gizi (hasil enrichment AI).
    private var nutritionRecords: [NutritionalInfo] {
        viewModel.records.compactMap { $0.nutrition }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        caloriesCard
                        macroGrid
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                    .appContentWidth()
                }
            }
            .navigationTitle("Statistic")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.refresh() }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Kartu kalori + grafik mingguan

    private var caloriesCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Calories").font(.headline).foregroundStyle(Color.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(viewModel.totalToday)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.primaryText)
                Text("Kcal").font(.headline).foregroundStyle(Color.primaryText)
                Spacer()
                Text("Target: ").font(.caption).foregroundStyle(Color.secondaryText)
                Text("\(target) Kcal").font(.caption.weight(.bold)).foregroundStyle(Color.primaryText)
            }
            weeklyChart
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(cornerRadius: 24)
    }

    private var weekData: [(label: String, calories: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = (cal.component(.weekday, from: today) + 5) % 7 // 0 = Senin
        guard let monday = cal.date(byAdding: .day, value: -weekday, to: today) else { return [] }
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: monday)!
            let total = viewModel.records
                .filter { cal.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.calories }
            return (labels[offset], total)
        }
    }

    private var weeklyChart: some View {
        let data = weekData
        let cal = Calendar.current
        let todayIndex = (cal.component(.weekday, from: Date()) + 5) % 7
        let maxValue = max(Double(data.map(\.calories).max() ?? 0), Double(target))

        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                let ratio = maxValue > 0 ? Double(item.calories) / maxValue : 0
                let percent = target > 0 ? Int(Double(item.calories) / Double(target) * 100) : 0
                let isToday = index == todayIndex
                VStack(spacing: 6) {
                    Text("\(percent)%")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isToday ? Color.brand : Color.secondaryText)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isToday ? AnyShapeStyle(Color.brand)
                                      : AnyShapeStyle(Color.brandSoft))
                        .frame(height: max(8, CGFloat(ratio) * 130))
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(isToday ? Color.primaryText : Color.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 180, alignment: .bottom)
        .animation(.easeOut(duration: 0.5), value: viewModel.records.count)
    }

    // MARK: Rata-rata gizi (dari hasil scan)

    private func average(_ keyPath: (NutritionalInfo) -> Double) -> Double {
        let values = nutritionRecords.map(keyPath)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func value(_ avg: Double, _ suffix: String) -> String {
        nutritionRecords.isEmpty ? "—" : String(format: "%.0f%@", avg, suffix)
    }

    private var macroGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Average per meal")
                .font(.headline).foregroundStyle(Color.primaryText)
                .padding(.horizontal, 4)
            LazyVGrid(columns: columns, spacing: 14) {
                statCard(icon: "fork.knife", tint: Color.macroProtein, title: "Protein",
                         value: value(average { $0.proteinGram }, "g"))
                statCard(icon: "leaf.fill", tint: Color.macroCarbs, title: "Carbs",
                         value: value(average { $0.carbsGram }, "g"))
                statCard(icon: "drop.fill", tint: Color.macroFat, title: "Fat",
                         value: value(average { $0.fatGram }, "g"))
                statCard(icon: "heart.fill", tint: Color.brand, title: "Health Score",
                         value: nutritionRecords.isEmpty ? "—"
                                : String(format: "%.1f/10", average { $0.healthScore }))
            }
        }
    }

    private func statCard(icon: String, tint: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Color.primaryText)
            }
            Text(value).font(.title3.weight(.bold)).foregroundStyle(Color.primaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .cardStyle(cornerRadius: 22)
    }
}
