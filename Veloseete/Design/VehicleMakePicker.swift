import SwiftUI

/// Featured + searchable make catalog for garage / edit vehicle.
enum VehicleMakeCatalog {
    /// Quick chips — global favourites plus well-known Chinese brands.
    static let featured: [String] = [
        "Toyota", "Honda", "BYD", "Geely", "Chery", "MG", "Haval", "Changan",
        "BMW", "Mercedes-Benz", "Audi", "Hyundai", "Kia", "Nissan", "Ford", "Volkswagen"
    ]

    /// Full list for the More drawer (A–Z). Includes Chinese OEMs and sub-brands.
    static let all: [String] = [
        "Acura", "Aito", "Alfa Romeo", "Aston Martin", "Audi", "Avatr",
        "BAIC", "Bentley", "BMW", "Bugatti", "Buick", "BYD",
        "Cadillac", "Changan", "Chery", "Chevrolet", "Chrysler", "Citroën",
        "Denza", "Dodge", "Dongfeng",
        "Exeed",
        "Ferrari", "Fiat", "Ford",
        "GAC", "Geely", "Genesis", "GMC", "Great Wall",
        "Haval", "Honda", "Hongqi", "Hyundai",
        "IM Motors", "Infiniti", "Isuzu",
        "Jaecoo", "Jaguar", "Jeep",
        "Kia",
        "Lamborghini", "Land Rover", "Leapmotor", "Lexus", "Li Auto", "Lincoln", "Lotus", "Lynk & Co",
        "Maserati", "Mazda", "McLaren", "Mercedes-Benz", "MG", "Mini", "Mitsubishi",
        "NIO", "Nissan",
        "Omoda", "Ora",
        "Peugeot", "Polestar", "Porsche",
        "Ram", "Renault", "Rolls-Royce",
        "SAIC", "Seat", "Seres", "Skoda", "Smart", "Subaru", "Suzuki",
        "Tank", "Tesla", "Toyota",
        "Volkswagen", "Volvo", "Voyah",
        "Wuling",
        "Xiaomi", "XPeng",
        "Zeekr"
    ].sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    static func matches(_ query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}

/// Horizontal make chips + More drawer (search). Choosing from More pins that make first.
struct VehicleMakeChipRow: View {
    @Binding var make: String
    @State private var showMore = false
    /// Make chosen from More — always shown as the leading chip while selected / sticky.
    @State private var pinnedMake: String?

    private var chips: [String] {
        var list = VehicleMakeCatalog.featured
        let pin = resolvedPin
        if let pin {
            list.removeAll { $0.caseInsensitiveCompare(pin) == .orderedSame }
            list.insert(pin, at: 0)
        }
        return list
    }

    private var resolvedPin: String? {
        if let pinnedMake, !pinnedMake.isEmpty { return pinnedMake }
        let current = make.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return nil }
        let inFeatured = VehicleMakeCatalog.featured.contains {
            $0.caseInsensitiveCompare(current) == .orderedSame
        }
        return inFeatured ? nil : current
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { name in
                    VSSelectableChip(title: name, selected: isSelected(name)) {
                        select(name, pinFromMore: false)
                    }
                }
                VSSelectableChip(title: "More", selected: false) {
                    showMore = true
                }
            }
        }
        .sheet(isPresented: $showMore) {
            VehicleMakeSearchSheet(selectedMake: make) { chosen in
                select(chosen, pinFromMore: true)
            }
            .presentationDetents([.medium, .large])
            .veloseeteSheet()
        }
        .onAppear {
            syncPinFromCurrentMake()
        }
        .onChange(of: make) { _, _ in
            syncPinFromCurrentMake()
        }
    }

    private func isSelected(_ name: String) -> Bool {
        make.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(name) == .orderedSame
    }

    private func select(_ name: String, pinFromMore: Bool) {
        UISelectionFeedbackGenerator().selectionChanged()
        make = name
        if pinFromMore {
            pinnedMake = name
        }
    }

    private func syncPinFromCurrentMake() {
        let current = make.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return }
        let inFeatured = VehicleMakeCatalog.featured.contains {
            $0.caseInsensitiveCompare(current) == .orderedSame
        }
        if !inFeatured {
            pinnedMake = current
        }
    }
}

private struct VehicleMakeSearchSheet: View {
    let selectedMake: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [String] {
        VehicleMakeCatalog.matches(query)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VS.Color.textTertiary)
                    TextField("Search makes", text: $query)
                        .font(VS.Typography.body(16))
                        .foregroundStyle(VS.Color.textPrimary)
                        .focused($searchFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            VSIcon(icon: .x, size: 14, weight: .bold, tint: VS.Color.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(VS.Color.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                if results.isEmpty {
                    VStack(spacing: 10) {
                        Text("No matches")
                            .font(VS.Typography.heading(17, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text("Try another spelling")
                            .font(VS.Typography.body(13))
                            .foregroundStyle(VS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results, id: \.self) { name in
                                Button {
                                    onSelect(name)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(name)
                                            .font(VS.Typography.heading(16, weight: .semibold))
                                            .foregroundStyle(VS.Color.textPrimary)
                                        Spacer()
                                        if name.caseInsensitiveCompare(selectedMake) == .orderedSame {
                                            VSIcon(icon: .checkCircle, size: 18, weight: .fill, tint: VS.Color.accent)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Rectangle()
                                    .fill(VS.Color.hairline.opacity(0.7))
                                    .frame(height: 1)
                                    .padding(.leading, 20)
                            }
                        }
                        .padding(.bottom, 28)
                    }
                }
            }
            .veloseetePage()
            .navigationTitle("Choose make")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(VS.Color.accent)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    searchFocused = true
                }
            }
        }
    }
}
