import SwiftUI

struct GarageView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var auth: AuthService
    var onComplete: (() -> Void)? = nil

    @State private var step = 1
    @State private var nickname = ""
    @State private var icon = "🚗"
    @State private var make = ""
    @State private var model = ""
    @State private var showMakeModel = false
    @State private var fuelType = "petrol"
    @State private var currency = "QAR"
    @State private var odometer = ""
    @State private var tankCapacity = ""
    @State private var showTank = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isRetrying = false

    private let fuelTypes = [
        ("petrol", "Petrol"),
        ("diesel", "Diesel"),
        ("hybrid", "Hybrid"),
        ("electric", "Electric")
    ]

    private let popularMakes = [
        "Toyota", "Honda", "Ford", "BMW", "Mercedes-Benz", "Audi",
        "Volkswagen", "Nissan", "Hyundai", "Kia", "Mazda", "Lexus"
    ]

    private let icons = ["🚗", "🚙", "🚕", "🚌", "🚐", "🏎️", "🚓", "🚑", "🚒", "🚚", "🚛", "🛻", "🏍️", "🛵", "🚜", "🚎"]

    var body: some View {
        VStack(spacing: 0) {
            accountBanner

            HStack {
                if step > 1 {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            step -= 1
                        }
                    } label: {
                        VSIcon(icon: .caretLeft, size: 18, weight: .bold, tint: VS.Color.textSecondary)
                            .frame(width: 40, height: 40)
                            .glassCard(radius: 20)
                    }
                }
                Spacer()
                Text("Step \(step) of 3")
                    .font(VS.Typography.body(13, weight: .medium))
                    .foregroundStyle(VS.Color.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                Group {
                    switch step {
                    case 1: stepBasics
                    case 2: stepFuel
                    default: stepOdometer
                    }
                }
                .padding(20)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(VS.Typography.body(13))
                    .foregroundStyle(VS.Color.error)
                    .padding(.horizontal, 20)
            }

            Button {
                Task { await advance() }
            } label: {
                HStack {
                    if isSubmitting { ProgressView().tint(VS.Color.navPill) }
                    Text(step == 3 ? "Finish setup" : "Continue")
                        .font(VS.Typography.heading(17))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canContinue ? VS.Color.accent : VS.Color.accent.opacity(0.35))
                .foregroundStyle(VS.Color.navPill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(!canContinue || isSubmitting)
            .buttonStyle(ScaleButtonStyle())
            .padding(20)
        }
        .background(VS.Color.bgPrimary.ignoresSafeArea())
        .onAppear {
            currency = Locale.current.currency?.identifier == "USD" ? "USD"
                : Locale.current.region?.identifier == "AE" ? "AED"
                : Locale.current.region?.identifier == "SA" ? "SAR"
                : "QAR"
        }
    }

    private var accountBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Signed in as")
                .font(VS.Typography.body(11, weight: .medium))
                .foregroundStyle(VS.Color.textTertiary)
            Text(auth.user?.email ?? "Unknown")
                .font(VS.Typography.heading(14))
                .foregroundStyle(VS.Color.textPrimary)

            Text("No vehicles found for this account yet. If this isn’t the email you use on the web app, sign out and sign in with that one — then tap Retry sync.")
                .font(VS.Typography.body(12))
                .foregroundStyle(VS.Color.textSecondary)

            if !store.loadWarnings.isEmpty {
                Text(store.loadWarnings.joined(separator: "\n"))
                    .font(VS.Typography.body(11))
                    .foregroundStyle(VS.Color.warning)
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        isRetrying = true
                        if let uid = auth.userId {
                            await store.loadAll(userId: uid)
                        }
                        isRetrying = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isRetrying { ProgressView().tint(VS.Color.accent) }
                        Text("Retry sync")
                            .font(VS.Typography.body(13, weight: .semibold))
                    }
                    .foregroundStyle(VS.Color.accent)
                }

                Button("Sign out") {
                    try? auth.signOut()
                }
                .font(VS.Typography.body(13, weight: .semibold))
                .foregroundStyle(VS.Color.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VS.Color.bgSecondary)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.white.opacity(0.08)), alignment: .bottom)
    }

    private var canContinue: Bool {
        switch step {
        case 1: return !nickname.trimmingCharacters(in: .whitespaces).isEmpty
        case 2: return !fuelType.isEmpty && !currency.isEmpty
        default: return Double(odometer) != nil && (Double(odometer) ?? 0) >= 0
        }
    }

    private var stepBasics: some View {
        VStack(alignment: .leading, spacing: 20) {
            titleBlock("Let's set up your first vehicle", "Takes about 30 seconds")

            fieldLabel("Vehicle name")
            TextField("My car", text: $nickname)
                .font(VS.Typography.heading(18))
                .foregroundStyle(VS.Color.textPrimary)
                .vsInputField()

            fieldLabel("Icon")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                ForEach(icons, id: \.self) { item in
                    Button {
                        icon = item
                    } label: {
                        FluentEmojiView(emoji: item, size: 26)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(icon == item ? VS.Color.accent.opacity(0.2) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(icon == item ? VS.Color.accent : Color.clear, lineWidth: 1.5)
                            )
                    }
                }
            }

            Button {
                withAnimation { showMakeModel.toggle() }
            } label: {
                Text(showMakeModel ? "Hide make & model" : "Add make & model (optional)")
                    .font(VS.Typography.body(14, weight: .medium))
                    .foregroundStyle(VS.Color.accent)
            }

            if showMakeModel {
                fieldLabel("Make")
                TextField("e.g. Toyota", text: $make)
                    .vsInputField()
                    .foregroundStyle(VS.Color.textPrimary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(popularMakes, id: \.self) { m in
                            Button(m) { make = m }
                                .font(VS.Typography.body(12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(make == m ? VS.Color.accent.opacity(0.2) : Color.white.opacity(0.06)))
                                .foregroundStyle(make == m ? VS.Color.accent : VS.Color.textSecondary)
                        }
                    }
                }

                fieldLabel("Model")
                TextField("e.g. Camry", text: $model)
                    .vsInputField()
                    .foregroundStyle(VS.Color.textPrimary)
            }
        }
    }

    private var stepFuel: some View {
        VStack(alignment: .leading, spacing: 20) {
            titleBlock("Fuel & region", "We've set a currency for your region")

            HStack {
                Text(currency)
                    .font(VS.Typography.heading(18))
                    .foregroundStyle(VS.Color.accent)
                Text("detected — you can change this later")
                    .font(VS.Typography.body(13))
                    .foregroundStyle(VS.Color.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            fieldLabel("Fuel type")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(fuelTypes, id: \.0) { type in
                    Button {
                        fuelType = type.0
                    } label: {
                        Text(type.1)
                            .font(VS.Typography.heading(15))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(fuelType == type.0 ? VS.Color.accent.opacity(0.18) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(fuelType == type.0 ? VS.Color.accent : Color.white.opacity(0.1), lineWidth: 1.5)
                            )
                            .foregroundStyle(VS.Color.textPrimary)
                    }
                }
            }

            fieldLabel("Currency")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["QAR", "AED", "SAR", "USD", "EUR", "GBP", "PKR", "INR"], id: \.self) { code in
                        Button(code) { currency = code }
                            .font(VS.Typography.body(13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(currency == code ? VS.Color.accent : Color.white.opacity(0.06)))
                            .foregroundStyle(currency == code ? VS.Color.navPill : VS.Color.textSecondary)
                    }
                }
            }
        }
    }

    private var stepOdometer: some View {
        VStack(alignment: .leading, spacing: 20) {
            titleBlock("Starting odometer", "Enter your vehicle's current odometer reading")

            fieldLabel("Current odometer (km)")
            TextField("e.g. 50000", text: $odometer)
                .keyboardType(.numberPad)
                .font(VS.Typography.heading(28, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
                .vsInputField()

            Button {
                withAnimation { showTank.toggle() }
            } label: {
                Text(showTank ? "Hide tank capacity" : "Add tank capacity (optional)")
                    .font(VS.Typography.body(14, weight: .medium))
                    .foregroundStyle(VS.Color.accent)
            }

            if showTank {
                fieldLabel("Tank capacity (L)")
                TextField("e.g. 55", text: $tankCapacity)
                    .keyboardType(.decimalPad)
                    .vsInputField()
                    .foregroundStyle(VS.Color.textPrimary)
            }
        }
    }

    private func titleBlock(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(VS.Typography.heading(28, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)
            Text(subtitle)
                .font(VS.Typography.body(15))
                .foregroundStyle(VS.Color.textSecondary)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(VS.Typography.body(12, weight: .medium))
            .foregroundStyle(VS.Color.textTertiary)
    }

    private func advance() async {
        errorMessage = nil
        if step < 3 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                step += 1
            }
            return
        }

        guard let odo = Double(odometer) else {
            errorMessage = "Please enter a valid odometer reading"
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await store.addVehicle(
                nickname: nickname.trimmingCharacters(in: .whitespaces),
                make: make.trimmingCharacters(in: .whitespaces).isEmpty ? "Unknown" : make.trimmingCharacters(in: .whitespaces),
                model: model.trimmingCharacters(in: .whitespaces).isEmpty ? "Unknown" : model.trimmingCharacters(in: .whitespaces),
                fuelType: fuelType,
                currentOdometer: odo,
                currency: currency,
                icon: icon,
                fuelTankCapacity: Double(tankCapacity)
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onComplete?()
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
