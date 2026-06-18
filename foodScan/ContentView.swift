//
//  ContentView.swift
//  foodScan
//
//  Root dengan custom tab bar bertema terang (putih + merah) dan tombol
//  Scan menonjol di tengah. Tab: Home, Statistic, [Scan], Riwayat, Menu.
//

import SwiftUI

enum AppTab: Int, CaseIterable {
    case home, stats, scan, history, menu

    var icon: String {
        switch self {
        case .home:    return "house.fill"
        case .stats:   return "chart.bar.fill"
        case .scan:    return "viewfinder"
        case .history: return "clock.fill"
        case .menu:    return "square.grid.2x2.fill"
        }
    }

    var title: String {
        switch self {
        case .home:    return "Home"
        case .stats:   return "Stats"
        case .scan:    return "Scan"
        case .history: return "History"
        case .menu:    return "Menu"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: UserSettings
    @State private var selectedTab: AppTab = .home

    var body: some View {
        Group {
            if settings.onboardingCompleted {
                ZStack(alignment: .bottom) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    CustomTabBar(selectedTab: $selectedTab)
                }
            } else {
                OnboardingView()
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .home:
            HomeView(viewModel: container.historyVM, scanVM: container.scanVM)
        case .stats:
            StatisticView(viewModel: container.historyVM)
        case .scan:
            ScanView(viewModel: container.scanVM) {
                Task { await container.historyVM.refresh() }
            }
        case .history:
            HistoryView(viewModel: container.historyVM)
        case .menu:
            MenuView()
        }
    }
}

// MARK: - Custom tab bar

private struct CustomTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                if tab == .scan {
                    scanButton
                } else {
                    tabButton(tab)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(
            Color.cardBackground
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(tab.title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selectedTab == tab ? Color.brand : Color.secondaryText)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var scanButton: some View {
        Button {
            selectedTab = .scan
        } label: {
            Image(systemName: "viewfinder")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(
                    LinearGradient(colors: [Color.brand, Color.brand.opacity(0.85)],
                                   startPoint: .top, endPoint: .bottom),
                    in: Circle()
                )
                .shadow(color: Color.brand.opacity(0.45), radius: 12, x: 0, y: 6)
                .offset(y: -18)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Menu

private struct MenuView: View {
    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        row("person.fill", "Profile") { ProfileView() }
                        row("scalemass.fill", "Weight") { WeightTrackingView() }
                        row("target", "Calorie Target") { TargetView() }
                        row("bell.fill", "Notifications") { NotificationsView() }
                        row("gearshape.fill", "Settings") { SettingsView() }
                        row("questionmark.circle.fill", "Help") { HelpView() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .padding(.bottom, 90)
                    .appContentWidth()
                }
            }
            .navigationTitle("Menu")
        }
        .navigationViewStyle(.stack)
    }

    private func row<Destination: View>(
        _ icon: String, _ title: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundStyle(Color.brand)
                    .frame(width: 38, height: 38)
                    .background(Color.brandSoft, in: Circle())
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(Color.secondaryText)
            }
            .cardStyle(cornerRadius: 18, padding: 14)
        }
        .buttonStyle(.plain)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let container = AppContainer()
        return ContentView()
            .environmentObject(container)
            .environmentObject(container.settings)
    }
}
