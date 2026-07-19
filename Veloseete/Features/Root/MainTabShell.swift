import SwiftUI
import PhotosUI
import UIKit
import Charts

enum AppTab: String, CaseIterable {
    case trips, fuel, analytics, details, service

    var label: String {
        switch self {
        case .trips: return "Drives"
        case .fuel: return "Fuel"
        case .analytics: return "Insights"
        case .details: return "Garage"
        case .service: return "Service"
        }
    }

    /// Same Phosphor set as web DashboardV2 bottom nav (+ map for Trips).
    var icon: VSIconName {
        switch self {
        case .trips: return .mapTrifold
        case .fuel: return .gasPump
        case .analytics: return .chartLine
        case .details: return .car
        case .service: return .wrench
        }
    }
}

struct MainTabShell: View {
    @EnvironmentObject private var store: DataStore
    @StateObject private var navChrome = BottomNavChrome()
    @State private var tab: AppTab = .trips
    @State private var showProfile = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .trips:
                    TripsView(onProfile: { showProfile = true })
                case .fuel:
                    DashboardView(onProfile: { showProfile = true })
                case .analytics:
                    AnalyticsView(onProfile: { showProfile = true })
                case .details:
                    DetailsListView(onProfile: { showProfile = true })
                case .service:
                    ServiceListView(onProfile: { showProfile = true })
                }
            }
            .coordinateSpace(name: "bottomNavScroll")

            BottomNavBar(active: $tab)
        }
        .environmentObject(navChrome)
        .onChange(of: tab) { _, _ in
            navChrome.reset()
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
    }
}

/// Shared top alignment for every primary tab. The trailing space is reserved for
/// the profile avatar supplied by `MainTabShell`, so local actions never collide.
struct MainTabHeader: View {
    @EnvironmentObject private var avatarStore: ProfileAvatarStore
    let title: String
    let subtitle: String?
    let onProfile: () -> Void

    init(_ title: String, subtitle: String? = nil, onProfile: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.onProfile = onProfile
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(VS.Typography.heading(28, weight: .bold))
                    .foregroundStyle(VS.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(VS.Typography.body(13))
                        .foregroundStyle(VS.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onProfile()
            } label: {
                ProfileAvatarView(image: avatarStore.image, size: 40)
                    .overlay(Circle().stroke(VS.Color.accent.opacity(0.24), lineWidth: 1))
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Open profile")
        }
        .frame(minHeight: 48, alignment: .top)
        .padding(.top, 8)
    }
}

struct BottomNavBar: View {
    @Binding var active: AppTab
    @EnvironmentObject private var navChrome: BottomNavChrome

    /// Matches web DashboardV2 (`#101012` selected pill, lime icon circle).
    private let selectedPill = VS.Color.navActive
    private let outerPill = VS.Color.navPill

    private var isCompact: Bool { navChrome.isCompact }

    private var iconSize: CGFloat { isCompact ? 18 : 22 }
    private var circleSize: CGFloat { isCompact ? 34 : 40 }
    private var itemMinHeight: CGFloat { isCompact ? 40 : 48 }
    private var outerPadding: CGFloat { isCompact ? 6 : 10 }
    private var horizontalInset: CGFloat { isCompact ? 28 : 16 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, item in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        active = item
                    }
                } label: {
                    HStack(spacing: isCompact ? 0 : 10) {
                        NavIconBubble(
                            icon: item.icon,
                            isActive: active == item,
                            iconSize: iconSize,
                            circleSize: circleSize,
                            activeTint: outerPill
                        )

                        if active == item && !isCompact {
                            Text(item.label)
                                .font(VS.Typography.heading(14))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    .padding(.horizontal, active == item && !isCompact ? 10 : (isCompact ? 4 : 6))
                    .frame(minHeight: itemMinHeight)
                    .background(
                        Capsule().fill(active == item ? selectedPill : .clear)
                    )
                }
                .buttonStyle(.plain)

                if index < AppTab.allCases.count - 1 {
                    Spacer(minLength: isCompact ? 6 : 4)
                }
            }
        }
        .padding(outerPadding)
        .frame(maxWidth: 420)
        .background(
            Capsule()
                .fill(outerPill)
                .shadow(color: .black.opacity(0.4), radius: isCompact ? 12 : 16, y: 4)
        )
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, isCompact ? 10 : 20)
    }
}

/// Lime circle + icon with a light pop when selected.
private struct NavIconBubble: View {
    let icon: VSIconName
    let isActive: Bool
    let iconSize: CGFloat
    let circleSize: CGFloat
    let activeTint: Color

    @State private var pop = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? VS.Color.accent : .clear)
                .frame(width: circleSize, height: circleSize)
                .scaleEffect(pop ? 1.08 : 1.0)

            VSIcon(
                icon: icon,
                size: iconSize,
                weight: isActive ? .fill : .regular,
                tint: isActive ? activeTint : VS.Color.textSecondary
            )
            .scaleEffect(pop ? 1.12 : 1.0)
            .rotationEffect(.degrees(pop ? -6 : 0))
        }
        .onChange(of: isActive) { _, active in
            guard active else {
                pop = false
                return
            }
            // Quick pop in, then settle — keeps it alive without bouncing forever.
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                pop = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
                    pop = false
                }
            }
        }
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
        .veloseetePage()
    }
}

struct DetailsListView: View {
    @EnvironmentObject private var store: DataStore
    let onProfile: () -> Void
    @State private var showAddVehicle = false
    @State private var editingVehicle: Vehicle?
    @State private var selectionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MainTabHeader("Garage", subtitle: "Your vehicles, readings and setup", onProfile: onProfile)

                HStack {
                    Spacer()
                    Button {
                        showAddVehicle = true
                    } label: {
                        HStack(spacing: 7) {
                            VSIcon(icon: .plusCircle, size: 17, weight: .fill, tint: VS.Color.navPill)
                            Text("Add vehicle")
                                .font(VS.Typography.body(13, weight: .bold))
                        }
                        .foregroundStyle(VS.Color.navPill)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(VS.Color.accent, in: Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Add vehicle")
                }

                if let selectionError {
                    Text(selectionError)
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.error)
                }

                if store.vehicles.isEmpty {
                    VStack(spacing: 12) {
                        VSIcon(icon: .car, size: 40, weight: .regular, tint: VS.Color.accent)
                        Text("Your garage is empty")
                            .font(VS.Typography.heading(18))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text("Add a vehicle to connect drives, fuel, service and odometer history.")
                            .font(VS.Typography.body(13))
                            .foregroundStyle(VS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Add your first vehicle") { showAddVehicle = true }
                            .font(VS.Typography.heading(14))
                            .foregroundStyle(VS.Color.navPill)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(VS.Color.accent, in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .glassCard(elevated: true)
                } else {
                    ForEach(store.vehicles) { vehicle in
                        garageVehicleCard(vehicle)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
            .tracksBottomNavScroll()
        }
        .veloseetePage()
        .sheet(isPresented: $showAddVehicle) {
            GarageView(onComplete: { showAddVehicle = false })
                .veloseeteSheet()
        }
        .sheet(item: $editingVehicle) { vehicle in
            VehicleEditorView(vehicle: vehicle)
                .veloseeteSheet()
        }
    }

    private func garageVehicleCard(_ vehicle: Vehicle) -> some View {
        let isCurrent = store.currentVehicle?.id == vehicle.id
        let refuels = store.fuelLogs.filter { $0.vehicleId == vehicle.id }.count
        let services = store.serviceLogs.filter { $0.vehicleId == vehicle.id }.count
        let drives = store.trips.filter { $0.vehicleId == vehicle.id }.count

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                FluentEmojiView(emoji: vehicle.icon ?? "🚗", size: 38)
                    .frame(width: 54, height: 54)
                    .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(vehicle.nickname)
                            .font(VS.Typography.heading(19, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)
                        if isCurrent {
                            Text("ACTIVE")
                                .font(VS.Typography.body(8, weight: .bold))
                                .tracking(0.7)
                                .foregroundStyle(VS.Color.navPill)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(VS.Color.accent, in: Capsule())
                        }
                    }
                    Text("\(vehicle.make) \(vehicle.model) · \(vehicle.fuelType.capitalized)")
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.textSecondary)
                }
                Spacer()
                Button { editingVehicle = vehicle } label: {
                    Text("Edit")
                        .font(VS.Typography.body(12, weight: .semibold))
                        .foregroundStyle(VS.Color.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(VS.Color.chip, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                garageMetric(DistanceFormat.formatOdometer(vehicle.currentOdometer, unit: store.defaultDistanceUnit), "ODOMETER")
                garageMetric(vehicle.fuelTankCapacity.map { String(format: "%.0f L", $0) } ?? "—", "TANK")
            }

            HStack(spacing: 0) {
                garageCount(drives, "Drives")
                Divider().overlay(VS.Color.divider)
                garageCount(refuels, "Refuels")
                Divider().overlay(VS.Color.divider)
                garageCount(services, "Services")
            }
            .frame(height: 42)

            if !isCurrent {
                Button {
                    Task {
                        do {
                            selectionError = nil
                            try await store.selectVehicle(vehicle.id)
                            UISelectionFeedbackGenerator().selectionChanged()
                        } catch {
                            selectionError = error.localizedDescription
                        }
                    }
                } label: {
                    Text("Make active vehicle")
                        .font(VS.Typography.heading(13))
                        .foregroundStyle(VS.Color.navPill)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(VS.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassCard(elevated: isCurrent)
    }

    private func garageMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(VS.Typography.heading(17))
                .foregroundStyle(VS.Color.textPrimary)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(VS.Typography.body(9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func garageCount(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(value)").font(VS.Typography.heading(15)).foregroundStyle(VS.Color.textPrimary)
            Text(label).font(VS.Typography.body(10)).foregroundStyle(VS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct VehicleEditorView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    @State private var nickname: String
    @State private var make: String
    @State private var model: String
    @State private var fuelType: String
    @State private var odometer: String
    @State private var tankCapacity: String
    @State private var currency: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(vehicle: Vehicle) {
        self.vehicle = vehicle
        _nickname = State(initialValue: vehicle.nickname)
        _make = State(initialValue: vehicle.make)
        _model = State(initialValue: vehicle.model)
        _fuelType = State(initialValue: vehicle.fuelType)
        _odometer = State(initialValue: String(format: "%.0f", vehicle.currentOdometer))
        _tankCapacity = State(initialValue: vehicle.fuelTankCapacity.map { String(format: "%.1f", $0) } ?? "")
        _currency = State(initialValue: vehicle.currency)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    TextField("Vehicle name", text: $nickname)
                    TextField("Make", text: $make)
                    TextField("Model", text: $model)
                    Picker("Fuel type", selection: $fuelType) {
                        ForEach(["petrol", "diesel", "hybrid", "electric"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
                Section("Readings & region") {
                    TextField("Current odometer", text: $odometer).keyboardType(.decimalPad)
                    TextField("Tank capacity (L)", text: $tankCapacity).keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        ForEach(["QAR", "AED", "SAR", "USD", "EUR", "GBP", "PKR", "INR"], id: \.self) { Text($0) }
                    }
                    Text("Use the physical dashboard reading when correcting the odometer. Drives remain estimates between verified readings.")
                        .font(VS.Typography.body(11))
                        .foregroundStyle(VS.Color.textTertiary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(VS.Color.error) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(VS.Color.bgPrimary)
            .navigationTitle("Edit vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private var canSave: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Double(odometer) != nil
    }

    private func save() async {
        guard let odometerValue = Double(odometer) else { return }
        isSaving = true
        defer { isSaving = false }
        var updated = vehicle
        updated.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.make = make.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.fuelType = fuelType
        updated.currentOdometer = odometerValue
        updated.fuelTankCapacity = Double(tankCapacity)
        updated.currency = currency
        do {
            try await store.updateVehicle(updated)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum AnalyticsPeriod: String, CaseIterable {
    case week, month, year, all
    var title: String { rawValue.capitalized }
    var days: Int? { self == .week ? 7 : self == .month ? 30 : self == .year ? 365 : nil }
}

private struct AnalyticsPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct AnalyticsView: View {
    @EnvironmentObject private var store: DataStore
    let onProfile: () -> Void
    @State private var period: AnalyticsPeriod = .month

    private var logs: [FuelLog] {
        guard let vehicleId = store.currentVehicle?.id else { return [] }
        let all = store.fuelLogs.filter { $0.vehicleId == vehicleId }.sorted { $0.timestamp < $1.timestamp }
        guard let days = period.days, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return all }
        return all.filter { $0.timestamp >= cutoff }
    }

    private var distance: Double {
        guard let first = logs.first, let last = logs.last else { return 0 }
        return max(0, last.odometerReading - first.odometerReading)
    }
    private var spent: Double { logs.reduce(0) { $0 + $1.totalCost } }
    private var liters: Double { logs.reduce(0) { $0 + $1.fuelVolume } }
    private var efficiency: Double? { distance > 0 ? liters / distance * 100 : nil }
    private var currency: String { store.currentVehicle?.currency ?? "QAR" }

    private var monthlySpend: [AnalyticsPoint] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: logs) { calendar.date(from: calendar.dateComponents([.year, .month], from: $0.timestamp)) ?? $0.timestamp }
        return grouped.map { AnalyticsPoint(date: $0.key, value: $0.value.reduce(0) { $0 + $1.totalCost }) }.sorted { $0.date < $1.date }
    }

    private var efficiencyTrend: [AnalyticsPoint] {
        guard logs.count > 1 else { return [] }
        return (1..<logs.count).compactMap { index in
            let previous = logs[index - 1], current = logs[index]
            let interval = current.odometerReading - previous.odometerReading
            guard interval > 0, current.isFullTank, previous.isFullTank else { return nil }
            return AnalyticsPoint(date: current.timestamp, value: current.fuelVolume / interval * 100)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MainTabHeader(
                    "Insights",
                    subtitle: store.currentVehicle.map { "\($0.nickname) · \($0.make) \($0.model)" } ?? "Your vehicle",
                    onProfile: onProfile
                )

                HStack(spacing: 7) {
                    ForEach(AnalyticsPeriod.allCases, id: \.self) { option in
                        Button(option.title) { period = option }
                            .font(VS.Typography.body(12, weight: .semibold))
                            .foregroundStyle(period == option ? VS.Color.navPill : VS.Color.textSecondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(period == option ? VS.Color.accent : VS.Color.chip, in: Capsule())
                    }
                }

                HStack(spacing: 12) {
                    analyticsMetric(CurrencyFormat.format(spent, currency: currency), "TOTAL SPENT")
                    analyticsMetric(DistanceFormat.formatDistance(distance, unit: store.defaultDistanceUnit), "DRIVEN")
                }

                HStack {
                    summaryRow("Cost per \(store.defaultDistanceUnit)", distance > 0 ? CurrencyFormat.format(spent / distance, currency: currency) : "—")
                    Divider().overlay(VS.Color.divider)
                    summaryRow("Avg efficiency", efficiency.map { String(format: "%.1f L/100", $0) } ?? "—")
                }
                .padding(16).glassCard()

                if monthlySpend.isEmpty {
                    analyticsEmptyState
                } else {
                    chartCard(title: "Monthly cost trend") {
                        Chart(monthlySpend) { point in
                            AreaMark(x: .value("Month", point.date), y: .value("Cost", point.value))
                                .foregroundStyle(LinearGradient(colors: [VS.Color.accent.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Month", point.date), y: .value("Cost", point.value))
                                .foregroundStyle(VS.Color.accent).lineStyle(.init(lineWidth: 2.5))
                            PointMark(x: .value("Month", point.date), y: .value("Cost", point.value)).foregroundStyle(VS.Color.accent)
                        }
                    }

                    if !efficiencyTrend.isEmpty {
                        chartCard(title: "Efficiency trend") {
                            Chart(efficiencyTrend) { point in
                                LineMark(x: .value("Date", point.date), y: .value("L/100 km", point.value))
                                    .foregroundStyle(VS.Color.success).lineStyle(.init(lineWidth: 2.5))
                                PointMark(x: .value("Date", point.date), y: .value("L/100 km", point.value)).foregroundStyle(VS.Color.success)
                            }
                        }
                    }
                }

                Text("Recent refuels").font(VS.Typography.heading(18)).foregroundStyle(VS.Color.textPrimary)
                VStack(spacing: 0) {
                    ForEach(logs.suffix(5).reversed()) { log in
                        RefuelRowView(log: log, unit: store.defaultDistanceUnit)
                        if log.id != logs.suffix(5).last?.id { Divider().overlay(VS.Color.divider) }
                    }
                }.padding(14).glassCard()
            }
            .padding(.horizontal, 16).padding(.bottom, 110).tracksBottomNavScroll()
        }
        .veloseetePage()
    }

    private func analyticsMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(VS.Typography.heading(24, weight: .bold)).foregroundStyle(VS.Color.textPrimary).minimumScaleFactor(0.7)
            Text(label).font(VS.Typography.body(9, weight: .bold)).tracking(0.8).foregroundStyle(VS.Color.textTertiary)
        }.frame(maxWidth: .infinity, minHeight: 86, alignment: .leading).padding(15).glassCard(elevated: true)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(VS.Typography.body(11)).foregroundStyle(VS.Color.textTertiary)
            Text(value).font(VS.Typography.heading(15)).foregroundStyle(VS.Color.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartCard<Content: View>(title: String, @ViewBuilder chart: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(VS.Typography.heading(17)).foregroundStyle(VS.Color.textSecondary)
            chart().frame(height: 210).chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }.chartYAxis { AxisMarks(position: .leading) }
        }.padding(16).glassCard(elevated: true)
    }

    private var analyticsEmptyState: some View {
        VStack(spacing: 10) {
            VSIcon(icon: .chartLine, size: 34, weight: .regular, tint: VS.Color.accent)
            Text("Add a couple of refuels to unlock trends").font(VS.Typography.heading(15)).foregroundStyle(VS.Color.textPrimary)
            Text("Your cost and efficiency charts will appear here.").font(VS.Typography.body(12)).foregroundStyle(VS.Color.textSecondary)
        }.frame(maxWidth: .infinity).padding(30).glassCard()
    }
}

struct ServiceListView: View {
    @EnvironmentObject private var store: DataStore
    let onProfile: () -> Void
    @State private var editingLog: ServiceLog?
    @State private var showEditor = false

    private var logs: [ServiceLog] {
        store.serviceLogs.filter { $0.vehicleId == store.currentVehicle?.id }.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MainTabHeader("Service", subtitle: store.currentVehicle?.nickname ?? "Your vehicle", onProfile: onProfile)

                serviceTrendCard

                PrimaryCTAButton(title: "Log service entry", icon: .wrench) {
                    editingLog = nil; showEditor = true
                }

                Text("Service history").font(VS.Typography.heading(19)).foregroundStyle(VS.Color.textPrimary)
                if logs.isEmpty {
                    Button { showEditor = true } label: {
                        VStack(spacing: 12) {
                            VSIcon(icon: .wrench, size: 34, weight: .regular, tint: VS.Color.accent)
                            Text("Log your first service").font(VS.Typography.heading(16)).foregroundStyle(VS.Color.textPrimary)
                            Text("Track maintenance, costs and what’s due next.").font(VS.Typography.body(12)).foregroundStyle(VS.Color.textSecondary)
                        }.frame(maxWidth: .infinity).padding(34).glassCard()
                    }.buttonStyle(.plain)
                } else {
                    VStack(spacing: 0) {
                        ForEach(logs) { log in
                            Button { editingLog = log; showEditor = true } label: { serviceRow(log) }.buttonStyle(.plain)
                            if log.id != logs.last?.id { Divider().overlay(VS.Color.divider) }
                        }
                    }.padding(.horizontal, 14).glassCard()
                }
            }.padding(.horizontal, 16).padding(.bottom, 110).tracksBottomNavScroll()
        }
        .veloseetePage()
        .sheet(isPresented: $showEditor) { ServiceEditorSheet(log: editingLog).veloseeteSheet() }
    }

    private var serviceTrendCard: some View {
        let latest = logs.first
        return VStack(alignment: .leading, spacing: 14) {
            Label("Service trend", systemImage: "chart.line.uptrend.xyaxis").font(VS.Typography.heading(17)).foregroundStyle(VS.Color.textPrimary)
            serviceFact("Current odometer", store.currentVehicle.map { DistanceFormat.formatOdometer($0.currentOdometer, unit: store.defaultDistanceUnit) } ?? "—")
            serviceFact("Last service", latest.map { "\($0.serviceType) · \($0.timestamp.formatted(date: .abbreviated, time: .omitted))" } ?? "No records yet")
            if let latest { serviceDueRow(latest) }
        }.padding(16).glassCard(elevated: true)
    }

    private func serviceFact(_ label: String, _ value: String) -> some View {
        HStack { Text(label).font(VS.Typography.body(12)).foregroundStyle(VS.Color.textTertiary); Spacer(); Text(value).font(VS.Typography.body(13, weight: .semibold)).foregroundStyle(VS.Color.textPrimary) }
        .padding(13).metricInset()
    }

    @ViewBuilder private func serviceDueRow(_ log: ServiceLog) -> some View {
        if let date = log.nextServiceDate {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
            serviceStatus(label: "Next service", value: days < 0 ? "Overdue by \(-days) days" : "Due in \(days) days", warning: days <= 7)
        } else if let next = log.nextServiceOdometer, let current = store.currentVehicle?.currentOdometer {
            let remaining = Int(next - current)
            serviceStatus(label: "Next service", value: remaining < 0 ? "Overdue by \(-remaining) km" : "\(remaining) km remaining", warning: remaining <= 500)
        }
    }

    private func serviceStatus(label: String, value: String, warning: Bool) -> some View {
        HStack { Text(label); Spacer(); Text(value).fontWeight(.semibold) }
            .font(VS.Typography.body(12)).foregroundStyle(warning ? VS.Color.warning : VS.Color.accent)
            .padding(13).background((warning ? VS.Color.warning : VS.Color.accent).opacity(0.09), in: RoundedRectangle(cornerRadius: VS.Radius.metric))
    }

    private func serviceRow(_ log: ServiceLog) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VSIcon(icon: .wrench, size: 18, weight: .regular, tint: VS.Color.accent).frame(width: 36, height: 36).background(VS.Color.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(log.serviceType).font(VS.Typography.heading(15)).foregroundStyle(VS.Color.textPrimary)
                Text("\(log.timestamp.formatted(date: .abbreviated, time: .omitted)) · \(DistanceFormat.formatOdometer(log.odometerReading, unit: store.defaultDistanceUnit))")
                    .font(VS.Typography.body(11)).foregroundStyle(VS.Color.textTertiary)
                if let description = log.description { Text(description).font(VS.Typography.body(11)).foregroundStyle(VS.Color.textSecondary).lineLimit(2) }
            }
            Spacer()
            if let cost = log.cost { Text(CurrencyFormat.format(cost, currency: log.currency)).font(VS.Typography.body(13, weight: .semibold)).foregroundStyle(VS.Color.textPrimary) }
        }.padding(.vertical, 14)
    }
}

struct ServiceEditorSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    let log: ServiceLog?

    @State private var serviceType = "Oil Change"
    @State private var customType = ""
    @State private var odometer = ""
    @State private var cost = ""
    @State private var notes = ""
    @State private var serviceDate = Date()
    @State private var nextOdometer = ""
    @State private var nextDate = Date()
    @State private var hasNextDate = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false

    private let types = ["Oil Change", "Tire Rotation", "Brake Service", "Air Filter", "Battery Replacement", "Transmission Service", "General Inspection", "Other"]
    private var vehicle: Vehicle? { store.currentVehicle }
    private var finalType: String { serviceType == "Other" ? customType.trimmingCharacters(in: .whitespacesAndNewlines) : serviceType }
    private var canSave: Bool { !finalType.isEmpty && (Double(odometer) ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fieldLabel("Service type")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(types, id: \.self) { type in
                            Button(type) { serviceType = type }
                                .font(VS.Typography.body(12, weight: .semibold))
                                .foregroundStyle(serviceType == type ? VS.Color.accent : VS.Color.textSecondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(serviceType == type ? VS.Color.accent.opacity(0.14) : VS.Color.chip, in: RoundedRectangle(cornerRadius: VS.Radius.metric))
                                .overlay(RoundedRectangle(cornerRadius: VS.Radius.metric).stroke(serviceType == type ? VS.Color.accent : VS.Color.divider))
                        }
                    }
                    if serviceType == "Other" { TextField("Service type", text: $customType).vsInputField().foregroundStyle(VS.Color.textPrimary) }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 7) { fieldLabel("Odometer"); TextField("Current km", text: $odometer).keyboardType(.decimalPad).vsInputField().foregroundStyle(VS.Color.textPrimary) }
                        VStack(alignment: .leading, spacing: 7) { fieldLabel("Cost (\(vehicle?.currency ?? "QAR"))"); TextField("Optional", text: $cost).keyboardType(.decimalPad).vsInputField().foregroundStyle(VS.Color.textPrimary) }
                    }

                    fieldLabel("Service date")
                    DatePicker("Service date", selection: $serviceDate, in: ...Date(), displayedComponents: .date).labelsHidden().datePickerStyle(.compact).tint(VS.Color.accent)

                    fieldLabel("Notes")
                    TextField("What was done?", text: $notes, axis: .vertical).lineLimit(3...6).vsInputField().foregroundStyle(VS.Color.textPrimary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("NEXT SERVICE REMINDER").font(VS.Typography.body(10, weight: .bold)).tracking(1).foregroundStyle(VS.Color.textTertiary)
                        TextField("Next odometer (optional)", text: $nextOdometer).keyboardType(.decimalPad).vsInputField().foregroundStyle(VS.Color.textPrimary)
                        Toggle("Add a due date", isOn: $hasNextDate).font(VS.Typography.body(13)).tint(VS.Color.accent)
                        if hasNextDate { DatePicker("Due date", selection: $nextDate, in: Date()..., displayedComponents: .date).tint(VS.Color.accent) }
                    }.padding(15).glassCard()

                    if let errorMessage { Text(errorMessage).font(VS.Typography.body(12)).foregroundStyle(VS.Color.error) }

                    if log != nil {
                        Button("Delete service entry", role: .destructive) { showDeleteConfirmation = true }
                            .font(VS.Typography.body(14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }.padding(20).padding(.bottom, 90)
            }
            .veloseetePage()
            .navigationTitle(log == nil ? "Log Service" : "Edit Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.foregroundStyle(VS.Color.textSecondary) }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryCTAButton(
                    title: log == nil ? "Save service" : "Save changes",
                    icon: .wrench,
                    isLoading: saving,
                    isEnabled: canSave
                ) {
                    Task { await save() }
                }
                .padding(20)
                .background(VS.Color.bgPrimary.opacity(0.96))
            }
            .onAppear { populate() }
            .alert("Delete service entry?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) { Task { await delete() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes the record from both iOS and the web app.") }
        }
    }

    private func fieldLabel(_ text: String) -> some View { Text(text).font(VS.Typography.body(11, weight: .medium)).foregroundStyle(VS.Color.textTertiary) }
    private func populate() {
        guard let log else {
            odometer = vehicle.map { String(format: "%.0f", $0.currentOdometer) } ?? ""
            return
        }
        serviceType = types.contains(log.serviceType) ? log.serviceType : "Other"
        customType = serviceType == "Other" ? log.serviceType : ""
        odometer = String(format: "%.0f", log.odometerReading)
        cost = log.cost.map { String(format: "%.2f", $0) } ?? ""
        notes = log.description ?? ""
        serviceDate = log.timestamp
        nextOdometer = log.nextServiceOdometer.map { String(format: "%.0f", $0) } ?? ""
        if let date = log.nextServiceDate { hasNextDate = true; nextDate = date }
    }
    private func save() async {
        guard let vehicle, let odo = Double(odometer) else { return }
        saving = true; errorMessage = nil; defer { saving = false }
        do {
            let input = FirestoreRepository.ServiceLogInput(vehicleId: vehicle.id, timestamp: serviceDate, odometerReading: odo, serviceType: finalType, description: notes.isEmpty ? nil : notes, cost: Double(cost), currency: vehicle.currency, nextServiceOdometer: Double(nextOdometer), nextServiceDate: hasNextDate ? nextDate : nil)
            try await store.saveServiceLog(id: log?.id, input: input)
            UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
    private func delete() async {
        guard let log else { return }
        do { try await store.deleteServiceLog(log); dismiss() } catch { errorMessage = error.localizedDescription }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var avatarStore: ProfileAvatarStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarError: String?
    @State private var isPreparingCrop = false
    @State private var isSavingAvatar = false
    @State private var cropDraft: AvatarCropDraft?
    /// Frozen UI avatar for the whole change/crop session — never follows drafts.
    @State private var displayAvatar: UIImage?
    @State private var isEditingDetails = false
    @State private var draftName = ""
    @State private var draftCurrency = "QAR"
    @State private var draftDistance = "km"
    @State private var isSavingDetails = false
    @State private var profileError: String?
    @State private var showReplayOnboarding = false
    @State private var showPermissionManager = false

    /// What the profile header shows: locked display during replace, else store.
    private var headerAvatar: UIImage? {
        displayAvatar ?? avatarStore.image
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        ZStack(alignment: .bottomTrailing) {
                            ProfileAvatarView(image: headerAvatar, size: 104)

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                VSIcon(icon: .plusCircle, size: 20, weight: .fill, tint: VS.Color.navPill)
                                    .frame(width: 34, height: 34)
                                    .background(VS.Color.accent, in: Circle())
                                    .overlay(Circle().stroke(VS.Color.bgSecondary, lineWidth: 3))
                            }
                            .accessibilityLabel(headerAvatar == nil ? "Add profile photo" : "Change profile photo")
                            .disabled(isPreparingCrop || isSavingAvatar || avatarStore.isReplacing)
                        }

                        VStack(spacing: 4) {
                            Text(store.userName.isEmpty ? "Your profile" : store.userName)
                                .font(VS.Typography.heading(20, weight: .bold))
                                .foregroundStyle(VS.Color.textPrimary)
                            Text(headerAvatar == nil ? "Add a photo from your library" : "Saved on this iPhone")
                                .font(VS.Typography.body(12))
                                .foregroundStyle(VS.Color.textTertiary)
                        }

                        if isSavingAvatar {
                            ProgressView("Saving photo…")
                                .font(VS.Typography.body(12))
                                .tint(VS.Color.accent)
                        } else if isPreparingCrop {
                            ProgressView("Opening photo…")
                                .font(VS.Typography.body(12))
                                .tint(VS.Color.accent)
                        } else if headerAvatar != nil {
                            HStack(spacing: 18) {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    Text("Change photo")
                                }
                                Button("Remove", role: .destructive) {
                                    guard let userId = auth.userId else { return }
                                    do {
                                        try avatarStore.remove(userId: userId)
                                        displayAvatar = nil
                                    } catch {
                                        avatarError = error.localizedDescription
                                    }
                                }
                            }
                            .font(VS.Typography.body(13, weight: .semibold))
                        }

                        if let avatarError {
                            Text(avatarError)
                                .font(VS.Typography.body(11))
                                .foregroundStyle(VS.Color.error)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section {
                    if isEditingDetails {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Display name").font(VS.Typography.body(11, weight: .medium)).foregroundStyle(VS.Color.textTertiary)
                            TextField("Your name", text: $draftName)
                                .font(VS.Typography.body(15))
                                .foregroundStyle(VS.Color.textPrimary)
                        }

                        Picker("Currency", selection: $draftCurrency) {
                            ForEach(["QAR", "AED", "SAR", "USD", "EUR", "GBP", "PKR", "INR"], id: \.self) { Text($0) }
                        }
                        Picker("Distance", selection: $draftDistance) {
                            Text("Kilometres").tag("km")
                            Text("Miles").tag("mi")
                        }
                    } else {
                        LabeledContent("Name", value: store.userName.isEmpty ? "—" : store.userName)
                        LabeledContent("Currency", value: store.userDocument?.profile.defaultCurrency ?? "QAR")
                        LabeledContent("Distance", value: store.defaultDistanceUnit == "mi" ? "Miles" : "Kilometres")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Email", value: auth.user?.email ?? "—")
                        Text("Your email is your sign-in ID and can’t be edited here.")
                            .font(VS.Typography.body(10))
                            .foregroundStyle(VS.Color.textTertiary)
                    }

                    if let profileError {
                        Text(profileError)
                            .font(VS.Typography.body(11))
                            .foregroundStyle(VS.Color.error)
                    }
                } header: {
                    HStack {
                        Text("Account")
                        Spacer()
                        Button(isEditingDetails ? "Cancel" : "Edit") {
                            if isEditingDetails {
                                isEditingDetails = false
                            } else {
                                prepareProfileDrafts()
                                isEditingDetails = true
                            }
                        }
                        .textCase(nil)
                        .font(VS.Typography.body(12, weight: .semibold))
                        .foregroundStyle(VS.Color.accent)
                    }
                } footer: {
                    if isEditingDetails {
                        Button {
                            Task { await saveProfileDetails() }
                        } label: {
                            HStack {
                                if isSavingDetails { ProgressView().tint(VS.Color.navPill) }
                                Text("Save profile")
                            }
                            .font(VS.Typography.heading(15))
                            .foregroundStyle(VS.Color.navPill)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(VS.Color.accent, in: RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingDetails)
                    }
                }
                .listRowBackground(VS.Color.bgSecondary)

                Section("App setup") {
                    Button {
                        showPermissionManager = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Manage trip permissions").foregroundStyle(VS.Color.textPrimary)
                                Text("Location, motion and notifications")
                                    .font(VS.Typography.body(11)).foregroundStyle(VS.Color.textTertiary)
                            }
                        } icon: {
                            VSIcon(icon: .target, size: 20, weight: .regular, tint: VS.Color.accent)
                        }
                    }

                    Button {
                        showReplayOnboarding = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Replay onboarding").foregroundStyle(VS.Color.textPrimary)
                                Text("See the Veloseete introduction again")
                                    .font(VS.Typography.body(11)).foregroundStyle(VS.Color.textTertiary)
                            }
                        } icon: {
                            VSIcon(icon: .roadHorizon, size: 20, weight: .regular, tint: VS.Color.accent)
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
            .veloseetePage()
            .foregroundStyle(VS.Color.textPrimary)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
            .fullScreenCover(item: $cropDraft, onDismiss: {
                abandonAvatarReplacementIfNeeded()
            }) { draft in
                ProfilePhotoCropView(image: draft.image) { cropped in
                    commitCroppedAvatar(cropped)
                } onCancel: {
                    cropDraft = nil
                }
            }
            .fullScreenCover(isPresented: $showReplayOnboarding) {
                TripPermissionsOnboardingView {
                    showReplayOnboarding = false
                }
            }
            .fullScreenCover(isPresented: $showPermissionManager) {
                TripPermissionsOnboardingView(startAtPermissions: true) {
                    showPermissionManager = false
                }
            }
            .onAppear {
                // Seed the frozen header from whatever is already committed.
                if displayAvatar == nil {
                    displayAvatar = avatarStore.image
                }
            }
            .onChange(of: avatarStore.image) { _, newValue in
                // Outside a replace session, keep the header in sync with the store.
                if !avatarStore.isReplacing {
                    displayAvatar = newValue
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                beginAvatarReplacement()
                isPreparingCrop = true
                avatarError = nil
                Task {
                    defer {
                        isPreparingCrop = false
                        selectedPhoto = nil
                    }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            throw ProfileAvatarError.invalidImage
                        }
                        guard let image = UIImage(data: data) else { throw ProfileAvatarError.invalidImage }
                        // Header stays on displayAvatar / store backup — only cropper gets the draft.
                        cropDraft = AvatarCropDraft(image: image)
                    } catch {
                        avatarError = error.localizedDescription
                        abandonAvatarReplacementIfNeeded()
                    }
                }
            }
        }
        .veloseeteSheet()
    }

    private func beginAvatarReplacement() {
        // Freeze whatever is currently shown so PhotosPicker / memory pressure cannot blank it.
        let committed = displayAvatar ?? avatarStore.image
        displayAvatar = committed?.stableCopy() ?? committed
        avatarStore.beginReplacement(preserving: displayAvatar)
    }

    private func commitCroppedAvatar(_ cropped: UIImage) {
        guard let userId = auth.userId else {
            cropDraft = nil
            abandonAvatarReplacementIfNeeded()
            avatarError = "Sign in again to save your photo."
            return
        }
        isSavingAvatar = true
        avatarError = nil
        defer { isSavingAvatar = false }
        do {
            try avatarStore.finishReplacement(image: cropped, userId: userId)
            displayAvatar = avatarStore.image
            cropDraft = nil
        } catch {
            cropDraft = nil
            abandonAvatarReplacementIfNeeded()
            avatarError = error.localizedDescription
        }
    }

    private func abandonAvatarReplacementIfNeeded() {
        // Only roll back when a replace session is still open (cancel / failed load).
        // Successful save clears `isReplacing` first so dismiss will not undo it.
        guard avatarStore.isReplacing else { return }
        displayAvatar = avatarStore.cancelReplacement()
    }

    private func prepareProfileDrafts() {
        draftName = store.userName
        draftCurrency = store.userDocument?.profile.defaultCurrency ?? "QAR"
        draftDistance = store.defaultDistanceUnit
        profileError = nil
    }

    private func saveProfileDetails() async {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSavingDetails = true
        profileError = nil
        defer { isSavingDetails = false }
        do {
            try await store.updateProfile(userName: name, currency: draftCurrency, distanceUnit: draftDistance)
            isEditingDetails = false
        } catch {
            profileError = error.localizedDescription
        }
    }
}

/// Holds a library photo while the cropper is open (does not replace the committed avatar).
struct AvatarCropDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

@MainActor
final class ProfileAvatarStore: ObservableObject {
    static let shared = ProfileAvatarStore()

    @Published private(set) var image: UIImage?
    /// True while PhotosPicker / cropper is in progress — `load` will not clobber `image`.
    @Published private(set) var isReplacing = false

    private var replacementBackup: UIImage?
    private let fileManager = FileManager.default
    private let maxDimension: CGFloat = 800

    private init() {}

    func load(userId: String?) {
        // Never wipe the on-screen avatar mid change/crop.
        guard !isReplacing else { return }

        guard let userId else {
            image = nil
            replacementBackup = nil
            return
        }

        let url = fileURL(for: userId)
        // Decode via Data so the bitmap is not purgeable under memory pressure.
        guard let data = try? Data(contentsOf: url),
              let loaded = UIImage(data: data)?.stableCopy() else {
            // Failed read must not blank an avatar that is already showing.
            return
        }
        image = loaded
    }

    func beginReplacement(preserving committed: UIImage?) {
        if !isReplacing {
            replacementBackup = (committed ?? image)?.stableCopy()
            isReplacing = true
        }
        // Keep publishing the committed photo for dashboard / trips / profile.
        if let backup = replacementBackup {
            image = backup
        }
    }

    @discardableResult
    func cancelReplacement() -> UIImage? {
        let restored = replacementBackup?.stableCopy() ?? replacementBackup
        image = restored
        replacementBackup = nil
        isReplacing = false
        return restored
    }

    func finishReplacement(image newImage: UIImage, userId: String) throws {
        try save(image: newImage, userId: userId)
        replacementBackup = nil
        isReplacing = false
    }

    func save(data: Data, userId: String) throws {
        guard let source = UIImage(data: data) else {
            throw ProfileAvatarError.invalidImage
        }
        try save(image: source, userId: userId)
    }

    func save(image source: UIImage, userId: String) throws {
        let normalized = resizedImage(source).stableCopy()
        guard let jpeg = normalized.jpegData(compressionQuality: 0.82) else {
            throw ProfileAvatarError.processingFailed
        }
        try fileManager.createDirectory(at: avatarDirectory, withIntermediateDirectories: true)
        try jpeg.write(to: fileURL(for: userId), options: .atomic)
        self.image = normalized
    }

    func remove(userId: String) throws {
        let url = fileURL(for: userId)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        image = nil
        replacementBackup = nil
        isReplacing = false
    }

    private var avatarDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Veloseete/Avatars", isDirectory: true)
    }

    private func fileURL(for userId: String) -> URL {
        let safeId = userId.replacingOccurrences(of: "/", with: "_")
        return avatarDirectory.appendingPathComponent("\(safeId).jpg")
    }

    private func resizedImage(_ source: UIImage) -> UIImage {
        let sourceSize = source.size
        let longestSide = max(sourceSize.width, sourceSize.height)
        guard longestSide > maxDimension else { return source.stableCopy() }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

extension UIImage {
    /// Copies into a non-purgeable bitmap so the avatar does not vanish under memory pressure.
    func stableCopy() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let size = self.size
        guard size.width > 0, size.height > 0 else { return self }
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

enum ProfileAvatarError: LocalizedError {
    case invalidImage
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "That photo could not be opened. Please choose another image."
        case .processingFailed: return "The photo could not be prepared for saving."
        }
    }
}

struct ProfileAvatarView: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    // Stable identity so SwiftUI does not drop the bitmap mid-picker.
                    .id(image.hashValue)
            } else {
                ZStack {
                    VS.Color.bgSecondary
                    VSIcon(icon: .user, size: size * 0.42, weight: .fill, tint: VS.Color.textSecondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: size > 60 ? 16 : 8, y: 5)
    }
}

struct ProfilePhotoCropView: View {
    let image: UIImage
    let onUse: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    private let cropSize: CGFloat = 310

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 7) {
                    Text("Reframe your photo")
                        .font(VS.Typography.heading(26, weight: .bold))
                        .foregroundStyle(VS.Color.textPrimary)
                    Text("Move and zoom until it feels right")
                        .font(VS.Typography.body(14))
                        .foregroundStyle(VS.Color.textSecondary)
                }

                cropCanvas

                HStack(spacing: 10) {
                    VSIcon(icon: .user, size: 15, weight: .regular, tint: VS.Color.textTertiary)
                    Slider(value: $zoom, in: 1...4)
                        .tint(VS.Color.accent)
                        .onChange(of: zoom) { _, newValue in
                            settledZoom = newValue
                            offset = constrained(offset, zoom: newValue)
                            settledOffset = offset
                        }
                    VSIcon(icon: .user, size: 22, weight: .fill, tint: VS.Color.textSecondary)
                }
                .padding(.horizontal, 26)

                Text("Only the circular area will appear in your profile")
                    .font(VS.Typography.body(11))
                    .foregroundStyle(VS.Color.textTertiary)

                Spacer()

                Button {
                    onUse(renderCrop())
                } label: {
                    Text("Use this photo")
                        .font(VS.Typography.heading(17))
                        .foregroundStyle(VS.Color.navPill)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(VS.Color.accent, in: RoundedRectangle(cornerRadius: VS.Radius.card, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }
            .padding(.top, 18)
            .veloseetePage()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(VS.Color.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            zoom = 1
                            settledZoom = 1
                            offset = .zero
                            settledOffset = .zero
                        }
                    }
                    .foregroundStyle(VS.Color.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var cropCanvas: some View {
        let base = baseImageSize
        return Image(uiImage: image)
            .resizable()
            .frame(width: base.width, height: base.height)
            .scaleEffect(zoom)
            .offset(offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = constrained(
                            CGSize(
                                width: settledOffset.width + value.translation.width,
                                height: settledOffset.height + value.translation.height
                            ),
                            zoom: zoom
                        )
                    }
                    .onEnded { _ in settledOffset = offset }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        zoom = min(max(settledZoom * value, 1), 4)
                        offset = constrained(offset, zoom: zoom)
                    }
                    .onEnded { _ in
                        settledZoom = zoom
                        settledOffset = offset
                    }
            )
            .frame(width: cropSize, height: cropSize)
            .clipShape(Circle())
            .overlay(Circle().stroke(VS.Color.accent, lineWidth: 3))
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 8).padding(-7))
            .shadow(color: VS.Color.accent.opacity(0.18), radius: 24)
            .contentShape(Circle())
    }

    private var baseImageSize: CGSize {
        let source = image.size
        let scale = max(cropSize / source.width, cropSize / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    private func constrained(_ proposed: CGSize, zoom: CGFloat) -> CGSize {
        let size = baseImageSize
        let maxX = max(0, (size.width * zoom - cropSize) / 2)
        let maxY = max(0, (size.height * zoom - cropSize) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func renderCrop() -> UIImage {
        let outputSize: CGFloat = 800
        let conversion = outputSize / cropSize
        let displayed = baseImageSize
        let drawSize = CGSize(
            width: displayed.width * zoom * conversion,
            height: displayed.height * zoom * conversion
        )
        let drawOrigin = CGPoint(
            x: ((cropSize - displayed.width * zoom) / 2 + offset.width) * conversion,
            y: ((cropSize - displayed.height * zoom) / 2 + offset.height) * conversion
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize), format: format).image { _ in
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }
}
