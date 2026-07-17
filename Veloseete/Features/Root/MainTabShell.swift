import SwiftUI

enum AppTab: String, CaseIterable {
    case overview, analytics, details, service, trips

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .analytics: return "Analytics"
        case .details: return "Details"
        case .service: return "Service"
        case .trips: return "Trips"
        }
    }

    /// Same Phosphor set as web DashboardV2 bottom nav (+ map for Trips).
    var icon: VSIconName {
        switch self {
        case .overview: return .gasPump
        case .analytics: return .chartLine
        case .details: return .fileText
        case .service: return .wrench
        case .trips: return .mapTrifold
        }
    }
}

struct MainTabShell: View {
    @EnvironmentObject private var store: DataStore
    @State private var tab: AppTab = .overview
    @State private var showProfile = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .overview:
                    DashboardView(onProfile: { showProfile = true })
                case .analytics:
                    PlaceholderPane(
                        title: "Analytics",
                        subtitle: "Charts and trends — next release",
                        icon: .chartLine
                    )
                case .details:
                    DetailsListView()
                case .service:
                    ServiceListView()
                case .trips:
                    TripsView()
                }
            }

            BottomNavBar(active: $tab)
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
    }
}

struct BottomNavBar: View {
    @Binding var active: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { item in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        active = item
                    }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(active == item ? VS.Color.accent : .clear)
                                .frame(width: 40, height: 40)
                            VSIcon(
                                icon: item.icon,
                                size: 20,
                                weight: active == item ? .fill : .regular,
                                tint: active == item ? VS.Color.navPill : VS.Color.textSecondary
                            )
                        }

                        if active == item {
                            Text(item.label)
                                .font(VS.Typography.heading(13))
                                .foregroundStyle(.white)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    .padding(.horizontal, active == item ? 8 : 4)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(active == item ? VS.Color.navActive : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            Capsule()
                .fill(VS.Color.navPill)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

struct PlaceholderPane: View {
    let title: String
    let subtitle: String
    let icon: VSIconName

    var body: some View {
        VStack(spacing: 12) {
            VSIcon(icon: icon, size: 40, weight: .regular, tint: VS.Color.accent)
            Text(title)
                .font(VS.Typography.heading(22))
                .foregroundStyle(VS.Color.textPrimary)
            Text(subtitle)
                .font(VS.Typography.body(14))
                .foregroundStyle(VS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 90)
    }
}

struct DetailsListView: View {
    @EnvironmentObject private var store: DataStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Refuel history")
                    .font(VS.Typography.heading(22))
                    .foregroundStyle(VS.Color.textPrimary)
                    .padding(.top, 16)

                let logs = store.fuelLogs.filter { $0.vehicleId == store.currentVehicle?.id }
                if logs.isEmpty {
                    Text("No refuels yet")
                        .foregroundStyle(VS.Color.textSecondary)
                } else {
                    ForEach(logs) { log in
                        RefuelRowView(log: log)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
    }
}

struct ServiceListView: View {
    @EnvironmentObject private var store: DataStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Service history")
                    .font(VS.Typography.heading(22))
                    .foregroundStyle(VS.Color.textPrimary)
                    .padding(.top, 16)

                let logs = store.serviceLogs.filter { $0.vehicleId == store.currentVehicle?.id }
                if logs.isEmpty {
                    Text("No service logs yet")
                        .foregroundStyle(VS.Color.textSecondary)
                } else {
                    ForEach(logs) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.serviceType.capitalized)
                                .font(VS.Typography.heading(15))
                                .foregroundStyle(VS.Color.textPrimary)
                            Text(log.timestamp.formatted(date: .abbreviated, time: .omitted))
                                .font(VS.Typography.body(12))
                                .foregroundStyle(VS.Color.textTertiary)
                            if let cost = log.cost {
                                Text(CurrencyFormat.format(cost, currency: log.currency))
                                    .font(VS.Typography.body(14, weight: .semibold))
                                    .foregroundStyle(VS.Color.accent)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAddVehicle = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Name", value: store.userName.isEmpty ? "—" : store.userName)
                    LabeledContent("Email", value: auth.user?.email ?? "—")
                    LabeledContent("Currency", value: store.userDocument?.profile.defaultCurrency ?? "QAR")
                    LabeledContent("Distance", value: store.defaultDistanceUnit)
                    LabeledContent("Synced refuels", value: "\(store.fuelLogs.count)")
                    LabeledContent("Vehicles", value: "\(store.vehicles.count)")
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section("Vehicles") {
                    ForEach(store.vehicles) { vehicle in
                        HStack {
                            FluentEmojiView(emoji: vehicle.icon ?? "🚗", size: 28)
                            VStack(alignment: .leading) {
                                Text(vehicle.nickname)
                                    .foregroundStyle(VS.Color.textPrimary)
                                Text("\(vehicle.make) \(vehicle.model)")
                                    .font(VS.Typography.body(12))
                                    .foregroundStyle(VS.Color.textTertiary)
                            }
                        }
                    }

                    Button {
                        showAddVehicle = true
                    } label: {
                        HStack(spacing: 8) {
                            VSIcon(icon: .plusCircle, size: 18, weight: .fill, tint: VS.Color.accent)
                            Text("Add vehicle")
                                .foregroundStyle(VS.Color.accent)
                        }
                    }
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section {
                    Button("Sign out", role: .destructive) {
                        try? auth.signOut()
                        dismiss()
                    }
                }
                .listRowBackground(VS.Color.bgSecondary)
            }
            .scrollContentBackground(.hidden)
            .background(VS.Color.bgPrimary)
            .foregroundStyle(VS.Color.textPrimary)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(VS.Color.accent)
                }
            }
            .sheet(isPresented: $showAddVehicle) {
                GarageView(onComplete: { showAddVehicle = false })
            }
        }
    }
}
