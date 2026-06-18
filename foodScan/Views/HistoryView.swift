//
//  HistoryView.swift
//  foodScan
//
//  Daftar riwayat scan (Persistence Agent) bergaya kartu putih tema terang.
//

import SwiftUI
import UIKit

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @EnvironmentObject private var settings: UserSettings
    @State private var detailRecord: ScanRecord?
    @State private var exportItem: ExportItem?

    private var dailyTarget: Int {
        viewModel.recommendation?.dailyTarget ?? settings.dailyCalorieTarget
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()
                if viewModel.records.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(groupedRecords, id: \.day) { group in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(dayLabel(group.day))
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(Color.primaryText)
                                        Spacer()
                                        Text("\(group.items.reduce(0) { $0 + $1.calories }) kcal")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.secondaryText)
                                    }
                                    .padding(.horizontal, 4)
                                    ForEach(group.items) { record in
                                        recordRow(record)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 100)
                        .appContentWidth()
                    }
                }
            }
            .navigationTitle("History")
            .sheet(item: $detailRecord) { record in
                MealDetailSheet(record: record, dailyTarget: dailyTarget, viewModel: viewModel)
            }
            .sheet(item: $exportItem) { item in
                ActivityView(activityItems: [item.url])
            }
            .toolbar {
                if !viewModel.records.isEmpty {
                    Menu {
                        Button {
                            exportHistory()
                        } label: {
                            Label("Export JSON", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            viewModel.clearAll()
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").tint(Color.brand)
                    }
                }
            }
            .task { await viewModel.refresh() }
        }
        .navigationViewStyle(.stack)
    }

    private func recordRow(_ record: ScanRecord) -> some View {
        HStack(spacing: 12) {
            Button {
                detailRecord = record
            } label: {
                HStack(spacing: 12) {
                    HistoryRow(record: record)
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(Color.secondaryText)
                }
            }
            .buttonStyle(.plain)
            Button(role: .destructive) {
                viewModel.delete(record)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.secondaryText)
            }
            .accessibilityLabel("Delete \(record.displayName)")
        }
        .cardStyle(cornerRadius: 18, padding: 12)
    }

    /// Riwayat dikelompokkan per hari, terbaru di atas.
    private var groupedRecords: [(day: Date, items: [ScanRecord])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: viewModel.records) { cal.startOfDay(for: $0.date) }
        return groups
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return Self.dayFmt.string(from: day)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(Color.secondaryText)
            Text("No history yet")
                .foregroundStyle(Color.secondaryText)
        }
        .cardStyle()
        .padding()
    }

    /// Encode seluruh riwayat ke JSON, tulis ke file sementara, lalu share.
    private func exportHistory() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(viewModel.records) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("foodscan-history.json")
        do {
            try data.write(to: url, options: .atomic)
            exportItem = ExportItem(url: url)
        } catch {
            // Diam-diam gagal; tidak memblokir UI.
        }
    }
}

/// Pembungkus Identifiable untuk presentasi share sheet.
struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Jembatan ke UIActivityViewController (share sheet sistem).
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Baris riwayat tema terang yang dipakai ulang.
struct HistoryRow: View {
    let record: ScanRecord

    var body: some View {
        HStack(spacing: 12) {
            if let image = ImageStore.load(record.imageFileName) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ZStack {
                    Color.brandSoft
                    Image(systemName: "fork.knife").foregroundStyle(Color.brand)
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primaryText)
                Text(record.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer()
            Text("\(record.calories) kcal")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.brand)
        }
    }
}
