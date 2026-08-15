import CoreLocation
import MapKit
import SwiftUI

/// Full-screen map + search to pick a petrol station for a refuel entry.
struct StationMapPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let initialStations: [StationLookup.Station]
    let initialSelection: StationLookup.Station?
    let onSelect: (StationLookup.Station) -> Void

    @State private var stations: [StationLookup.Station]
    @State private var selected: StationLookup.Station?
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var mapPosition: MapCameraPosition
    @State private var searchCenter: CLLocationCoordinate2D?
    @State private var errorMessage: String?

    init(
        initialStations: [StationLookup.Station],
        initialSelection: StationLookup.Station?,
        onSelect: @escaping (StationLookup.Station) -> Void
    ) {
        self.initialStations = initialStations
        self.initialSelection = initialSelection
        self.onSelect = onSelect
        _stations = State(initialValue: initialStations)
        _selected = State(initialValue: initialSelection)

        if let pick = initialSelection {
            _mapPosition = State(
                initialValue: .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: pick.latitude, longitude: pick.longitude),
                        latitudinalMeters: 1_800,
                        longitudinalMeters: 1_800
                    )
                )
            )
        } else if let first = initialStations.first {
            _mapPosition = State(
                initialValue: .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                        latitudinalMeters: 2_400,
                        longitudinalMeters: 2_400
                    )
                )
            )
        } else {
            _mapPosition = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $mapPosition) {
                    UserAnnotation()

                    ForEach(stations) { station in
                        Annotation(station.name, coordinate: station.coordinate, anchor: .bottom) {
                            StationMapPin(isSelected: selected?.id == station.id)
                                .onTapGesture {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    selected = station
                                    focus(on: station)
                                }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.gasStation])))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .ignoresSafeArea(edges: .bottom)
                .onMapCameraChange(frequency: .onEnd) { context in
                    searchCenter = context.camera.centerCoordinate
                }

                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    if isSearching {
                        ProgressView()
                            .tint(VS.Color.accent)
                            .padding(.top, 10)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(12))
                            .foregroundStyle(VS.Color.warning)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 0)

                    bottomPanel
                }
            }
            .veloseetePage()
            .navigationTitle("Pick station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VS.Color.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nearby") {
                        Task { await loadNearby(recenter: true) }
                    }
                    .font(VS.Typography.body(14, weight: .semibold))
                    .foregroundStyle(VS.Color.accent)
                    .disabled(isSearching)
                }
            }
            .task {
                if stations.isEmpty {
                    await loadNearby(recenter: true)
                }
            }
        }
        .presentationDetents([.large])
        .veloseeteSheet()
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(VS.Color.textTertiary)
            TextField("Search WOQOD, Shell, area…", text: $searchText)
                .font(VS.Typography.body(15))
                .foregroundStyle(VS.Color.textPrimary)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit {
                    Task { await runSearch() }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Task { await loadNearby(recenter: false) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(VS.Color.textTertiary)
                }
            }
            Button {
                Task { await runSearch() }
            } label: {
                Text("Go")
                    .font(VS.Typography.body(13, weight: .bold))
                    .foregroundStyle(VS.Color.navPill)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(VS.Color.accent, in: Capsule())
            }
            .disabled(isSearching)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: VS.Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VS.Radius.chip, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if stations.isEmpty && !isSearching {
                Text("No stations on the map yet — search a brand or tap Nearby.")
                    .font(VS.Typography.body(13))
                    .foregroundStyle(VS.Color.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stations.prefix(12)) { station in
                            let isOn = selected?.id == station.id
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                selected = station
                                focus(on: station)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name)
                                        .font(VS.Typography.body(13, weight: .semibold))
                                        .lineLimit(1)
                                    Text(Self.distanceText(station.distanceMeters))
                                        .font(VS.Typography.body(11))
                                        .opacity(0.8)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(isOn ? VS.Color.accent : VS.Color.chip))
                                .foregroundStyle(isOn ? VS.Color.navPill : VS.Color.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let selected {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.name)
                            .font(VS.Typography.heading(16))
                            .foregroundStyle(VS.Color.textPrimary)
                            .lineLimit(2)
                        Text(Self.distanceText(selected.distanceMeters) + " · tap Use station")
                            .font(VS.Typography.body(12))
                            .foregroundStyle(VS.Color.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onSelect(selected)
                        dismiss()
                    } label: {
                        Text("Use station")
                            .font(VS.Typography.body(14, weight: .bold))
                            .foregroundStyle(VS.Color.navPill)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(VS.Color.accent, in: Capsule())
                    }
                }
            }
        }
        .padding(16)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: VS.Radius.card, topTrailingRadius: VS.Radius.card)
                .fill(VS.Color.bgPrimary.opacity(0.96))
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 36, height: 4)
                        .padding(.top, 8)
                }
                .shadow(color: .black.opacity(0.35), radius: 18, y: -6)
        )
    }

    private func focus(on station: StationLookup.Station) {
        withAnimation(.easeInOut(duration: 0.35)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: station.coordinate,
                    latitudinalMeters: 1_200,
                    longitudinalMeters: 1_200
                )
            )
        }
    }

    private func loadNearby(recenter: Bool) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        let center: CLLocationCoordinate2D
        if let searchCenter {
            center = searchCenter
        } else if let user = await StationLookup.currentUserCoordinate() {
            center = user
        } else {
            errorMessage = "Couldn't get a location for nearby pumps."
            return
        }

        let found = await StationLookup.searchPetrolStations(query: "", near: center, limit: 16)
        stations = found
        if found.isEmpty {
            errorMessage = "No pumps near this map area."
        }
        if recenter, let first = found.first {
            focus(on: first)
            if selected == nil { selected = first }
        }
    }

    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            await loadNearby(recenter: false)
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        let center: CLLocationCoordinate2D
        if let searchCenter {
            center = searchCenter
        } else if let selected {
            center = selected.coordinate
        } else if let first = stations.first {
            center = first.coordinate
        } else if let user = await StationLookup.currentUserCoordinate() {
            center = user
        } else {
            errorMessage = "Move the map or enable location, then search."
            return
        }

        let found = await StationLookup.searchPetrolStations(query: query, near: center, limit: 20)
        stations = found
        if found.isEmpty {
            errorMessage = "Nothing matched “\(query)” here."
            return
        }
        selected = found.first
        if let first = found.first {
            focus(on: first)
        }
    }

    private static func distanceText(_ meters: Double) -> String {
        if meters < 80 { return "At the pump" }
        if meters < 1_000 { return String(format: "%.0f m", meters) }
        return String(format: "%.1f km", meters / 1_000)
    }
}

private struct StationMapPin: View {
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected ? VS.Color.accent : VS.Color.bgPrimary)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle().strokeBorder(isSelected ? Color.black.opacity(0.2) : VS.Color.accent, lineWidth: 2)
                    )
                Image(systemName: "fuelpump.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isSelected ? VS.Color.navPill : VS.Color.accent)
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)

            Triangle()
                .fill(isSelected ? VS.Color.accent : VS.Color.bgPrimary)
                .frame(width: 12, height: 8)
                .offset(y: -1)
        }
        .scaleEffect(isSelected ? 1.12 : 1)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private extension StationLookup.Station {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
