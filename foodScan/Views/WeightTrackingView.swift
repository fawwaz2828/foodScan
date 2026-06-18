//
//  WeightTrackingView.swift
//  foodScan
//
//  Pelacakan berat badan: catat berat berkala, lihat tren, dan jaga agar
//  berat terkini di profil tetap sinkron. Disimpan lokal di UserDefaults.
//

import SwiftUI

// MARK: - Model

struct WeightEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    let date: Date
    let weightKg: Double

    private enum CodingKeys: String, CodingKey { case id, date, weightKg }
}

// MARK: - Store (UserDefaults)

final class WeightStore: ObservableObject {
    @Published private(set) var entries: [WeightEntry] = []

    private let key = "weight.entries"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var latest: WeightEntry? { entries.last }

    func add(_ kg: Double, date: Date = Date()) {
        entries.append(WeightEntry(date: date, weightKg: kg))
        entries.sort { $0.date < $1.date }
        save()
    }

    func delete(_ entry: WeightEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let arr = try? JSONDecoder().decode([WeightEntry].self, from: data) else { return }
        entries = arr.sorted { $0.date < $1.date }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - View

struct WeightTrackingView: View {
    @EnvironmentObject private var settings: UserSettings
    @StateObject private var store = WeightStore()
    @State private var draft: Double = 0

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    logCard
                    if store.entries.count >= 2 { chartCard }
                    if !store.entries.isEmpty { historyCard }
                }
                .padding(20)
                .appContentWidth()
            }
        }
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if draft == 0 { draft = store.latest?.weightKg ?? settings.weightKg } }
    }

    // MARK: Cards

    private var summaryCard: some View {
        let current = store.latest?.weightKg ?? settings.weightKg
        let change = store.entries.count >= 2
            ? current - store.entries.first!.weightKg : 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("Current weight")
                .font(.caption.weight(.medium)).foregroundStyle(Color.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", current))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.primaryText)
                Text("kg").font(.headline).foregroundStyle(Color.secondaryText)
                Spacer()
                if change != 0 {
                    Label(String(format: "%+.1f kg", change),
                          systemImage: change < 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(change < 0 ? Color.macroProtein : Color.brand)
                }
            }
            Text("Goal: \(settings.goal.label)")
                .font(.footnote).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log weight")
                .font(.headline).foregroundStyle(Color.primaryText)
            HStack {
                Button { draft = max(30, draft - 0.1) } label: { Image(systemName: "minus.circle.fill") }
                Spacer()
                Text(String(format: "%.1f kg", draft))
                    .font(.title3.weight(.bold)).foregroundStyle(Color.primaryText)
                Spacer()
                Button { draft = min(300, draft + 0.1) } label: { Image(systemName: "plus.circle.fill") }
            }
            .font(.title2)
            .tint(Color.brand)
            Button {
                let kg = (draft * 10).rounded() / 10
                store.add(kg)
                settings.weightKg = kg          // jaga profil tetap terkini
            } label: {
                Label("Add entry", systemImage: "checkmark")
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var chartCard: some View {
        let entries = store.entries
        let weights = entries.map(\.weightKg)
        let minW = (weights.min() ?? 0) - 0.5
        let maxW = (weights.max() ?? 1) + 0.5
        let range = max(maxW - minW, 0.1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Trend")
                .font(.headline).foregroundStyle(Color.primaryText)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let stepX = entries.count > 1 ? w / CGFloat(entries.count - 1) : w
                let points = entries.enumerated().map { i, e in
                    CGPoint(x: CGFloat(i) * stepX,
                            y: h - CGFloat((e.weightKg - minW) / range) * h)
                }
                ZStack {
                    Path { p in
                        for (i, pt) in points.enumerated() {
                            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                        }
                    }
                    .stroke(Color.brand, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                        Circle().fill(Color.brand)
                            .frame(width: 6, height: 6)
                            .position(pt)
                    }
                }
            }
            .frame(height: 140)
            HStack {
                Text(String(format: "%.1f kg", weights.first ?? 0))
                Spacer()
                Text(String(format: "%.1f kg", weights.last ?? 0))
            }
            .font(.caption2).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.headline).foregroundStyle(Color.primaryText)
            ForEach(store.entries.reversed()) { entry in
                HStack {
                    Text(entry.date, style: .date)
                        .font(.subheadline).foregroundStyle(Color.primaryText)
                    Spacer()
                    Text(String(format: "%.1f kg", entry.weightKg))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.brand)
                    Button(role: .destructive) {
                        store.delete(entry)
                    } label: {
                        Image(systemName: "trash").font(.caption).foregroundStyle(Color.secondaryText)
                    }
                    .padding(.leading, 8)
                }
                if entry.id != store.entries.first?.id {
                    Divider().overlay(Color.black.opacity(0.05))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
