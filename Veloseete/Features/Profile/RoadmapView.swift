import SwiftUI

@MainActor
final class ProductVoiceStore: ObservableObject {
    @Published var items: [RoadmapItem] = []
    @Published var votedItemIds: Set<String> = []
    @Published var myRequests: [FeatureRequest] = []
    @Published var openRequests: [FeatureRequest] = []
    @Published var isModerator = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(userId: String?, email: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let config = await FirestoreRepository.shared.fetchModeratorConfig()
        isModerator = ProductModeration.isModerator(email: email, userId: userId, config: config)

        do {
            items = try await FirestoreRepository.shared.fetchRoadmapItems()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        if let userId {
            votedItemIds = (try? await FirestoreRepository.shared.fetchVotedItemIds(userId: userId)) ?? []
            myRequests = ((try? await FirestoreRepository.shared.fetchFeatureRequests(userId: userId, status: nil)) ?? [])
                .filter { $0.status == .open }
        }

        if isModerator {
            openRequests = (try? await FirestoreRepository.shared.fetchFeatureRequests(status: .open)) ?? []
        }
    }

    func toggleVote(itemId: String, userId: String) async {
        let currentlyVoted = votedItemIds.contains(itemId)
        withAnimation(.snappy(duration: 0.2)) {
            if currentlyVoted {
                votedItemIds.remove(itemId)
            } else {
                votedItemIds.insert(itemId)
            }
            if let index = items.firstIndex(where: { $0.id == itemId }) {
                items[index].voteCount = max(0, items[index].voteCount + (currentlyVoted ? -1 : 1))
            }
        }
        do {
            let voted = try await FirestoreRepository.shared.toggleRoadmapVote(itemId: itemId, userId: userId)
            withAnimation(.snappy(duration: 0.2)) {
                if voted {
                    votedItemIds.insert(itemId)
                } else {
                    votedItemIds.remove(itemId)
                }
            }
        } catch {
            withAnimation(.snappy(duration: 0.2)) {
                if currentlyVoted {
                    votedItemIds.insert(itemId)
                } else {
                    votedItemIds.remove(itemId)
                }
                if let index = items.firstIndex(where: { $0.id == itemId }) {
                    items[index].voteCount = max(0, items[index].voteCount + (currentlyVoted ? 1 : -1))
                }
            }
            errorMessage = error.localizedDescription
        }
    }

    func submitFeedback(userId: String, authorName: String, message: String) async throws {
        try await FirestoreRepository.shared.submitProductFeedback(
            userId: userId,
            authorName: authorName,
            message: message
        )
    }

    func submitRequest(userId: String, authorName: String, title: String, detail: String) async throws {
        try await FirestoreRepository.shared.submitFeatureRequest(
            userId: userId,
            authorName: authorName,
            title: title,
            detail: detail
        )
        await load(userId: userId, email: AuthService.shared.user?.email)
    }

    func addItem(title: String, detail: String, status: RoadmapStatus) async throws {
        _ = try await FirestoreRepository.shared.addRoadmapItem(title: title, detail: detail, status: status)
        await load(userId: AuthService.shared.userId, email: AuthService.shared.user?.email)
    }

    func setStatus(_ item: RoadmapItem, status: RoadmapStatus) async {
        do {
            try await FirestoreRepository.shared.updateRoadmapStatus(itemId: item.id, status: status)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].status = status
                items[index].releasedAt = status == .released ? Date() : nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func promote(_ request: FeatureRequest) async {
        do {
            try await FirestoreRepository.shared.promoteFeatureRequest(request)
            await load(userId: AuthService.shared.userId, email: AuthService.shared.user?.email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func decline(_ request: FeatureRequest) async {
        do {
            try await FirestoreRepository.shared.declineFeatureRequest(requestId: request.id)
            openRequests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct FeedbackComposerView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: VS.Spacing.module) {
                Text("What’s working, what’s missing, what felt off. This goes to the Veloseete inbox — not a public thread.")
                    .font(VS.Typography.body(14))
                    .foregroundStyle(VS.Color.textSecondary)

                TextEditor(text: $message)
                    .font(VS.Typography.body(16))
                    .foregroundStyle(VS.Color.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .vsInputField()

                if let errorMessage {
                    Text(errorMessage)
                        .font(VS.Typography.body(12))
                        .foregroundStyle(VS.Color.error)
                }

                Spacer(minLength: 0)

                PrimaryCTAButton(title: "Send feedback", icon: .fileText, isLoading: isSending, isEnabled: canSend) {
                    Task { await send() }
                }
            }
            .padding(VS.Spacing.sheetInset)
            .veloseetePage()
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .veloseeteSheet()
    }

    private func send() async {
        guard let userId = auth.userId else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await FirestoreRepository.shared.submitProductFeedback(
                userId: userId,
                authorName: store.userName.isEmpty ? (auth.user?.email ?? "Driver") : store.userName,
                message: trimmed
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct FeatureRequestComposerView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var voice: ProductVoiceStore
    var asModeratorItem: Bool = false

    @State private var title = ""
    @State private var detail = ""
    @State private var status: RoadmapStatus = .upcoming
    @State private var isSending = false
    @State private var errorMessage: String?

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VS.Spacing.module) {
                    Text(asModeratorItem
                         ? "This lands on the public roadmap immediately."
                         : "Describe the feature. If it fits the product, it can be added to the roadmap.")
                        .font(VS.Typography.body(14))
                        .foregroundStyle(VS.Color.textSecondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Title")
                            .font(VS.Typography.body(13, weight: .medium))
                            .foregroundStyle(VS.Color.textTertiary)
                        TextField("CarPlay live trip", text: $title)
                            .font(VS.Typography.heading(22, weight: .semibold))
                            .foregroundStyle(VS.Color.textPrimary)
                            .vsInputField()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Detail")
                            .font(VS.Typography.body(13, weight: .medium))
                            .foregroundStyle(VS.Color.textTertiary)
                        TextEditor(text: $detail)
                            .font(VS.Typography.body(16))
                            .foregroundStyle(VS.Color.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .vsInputField()
                    }

                    if asModeratorItem {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Status")
                                .font(VS.Typography.body(13, weight: .medium))
                                .foregroundStyle(VS.Color.textTertiary)
                            HStack(spacing: 8) {
                                ForEach(RoadmapStatus.allCases) { option in
                                    VSSelectableChip(title: option.label, selected: status == option) {
                                        status = option
                                    }
                                }
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(12))
                            .foregroundStyle(VS.Color.error)
                    }

                    PrimaryCTAButton(
                        title: asModeratorItem ? "Add to roadmap" : "Send request",
                        icon: asModeratorItem ? .target : .plusCircle,
                        isLoading: isSending,
                        isEnabled: canSend
                    ) {
                        Task { await send() }
                    }
                }
                .padding(VS.Spacing.sheetInset)
            }
            .veloseetePage()
            .navigationTitle(asModeratorItem ? "Add to roadmap" : "Request a feature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .veloseeteSheet()
    }

    private func send() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            if asModeratorItem {
                try await voice.addItem(title: trimmedTitle, detail: trimmedDetail, status: status)
            } else {
                guard let userId = auth.userId else { return }
                try await voice.submitRequest(
                    userId: userId,
                    authorName: store.userName.isEmpty ? (auth.user?.email ?? "Driver") : store.userName,
                    title: trimmedTitle,
                    detail: trimmedDetail
                )
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RoadmapView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = ProductVoiceStore()
    @State private var showRequest = false
    @State private var showAddItem = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VS.Spacing.floatStack) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Roadmap")
                            .font(VS.Typography.heading(28, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text("Vote the work you want next. Requests land here after moderation.")
                            .font(VS.Typography.body(14))
                            .foregroundStyle(VS.Color.textSecondary)
                    }

                    if let errorMessage = voice.errorMessage {
                        Text(errorMessage)
                            .font(VS.Typography.body(12))
                            .foregroundStyle(VS.Color.error)
                    }

                    if voice.isModerator, !voice.openRequests.isEmpty {
                        requestsInbox
                    }

                    if voice.isLoading && voice.items.isEmpty {
                        ProgressView()
                            .tint(VS.Color.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if voice.items.isEmpty {
                        emptyRoadmap
                    } else {
                        ForEach(RoadmapStatus.allCases) { status in
                            let bucket = voice.items.filter { $0.status == status }
                            if !bucket.isEmpty {
                                timelineSection(status: status, items: bucket)
                            }
                        }
                    }

                    if !voice.myRequests.isEmpty, !voice.isModerator {
                        myRequestsSection
                    }

                    VStack(spacing: VS.Spacing.stack) {
                        PrimaryCTAButton(title: "Request a feature", icon: .plusCircle) {
                            showRequest = true
                        }
                        if voice.isModerator {
                            Button {
                                showAddItem = true
                            } label: {
                                Text("Add to roadmap")
                                    .font(VS.Typography.heading(15))
                                    .foregroundStyle(VS.Color.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(hex: 0x1C1C1E), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, VS.Spacing.pageInset)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .veloseetePage()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ModalCloseButton { dismiss() }
                }
            }
            .task {
                await voice.load(userId: auth.userId, email: auth.user?.email)
            }
            .refreshable {
                await voice.load(userId: auth.userId, email: auth.user?.email)
            }
            .sheet(isPresented: $showRequest) {
                FeatureRequestComposerView(voice: voice)
            }
            .sheet(isPresented: $showAddItem) {
                FeatureRequestComposerView(voice: voice, asModeratorItem: true)
            }
        }
        .presentationDetents([.large])
        .veloseeteSheet()
    }

    private var emptyRoadmap: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing on the board yet")
                .font(VS.Typography.heading(16))
                .foregroundStyle(VS.Color.textPrimary)
            Text("Request a feature and it can be added here after review.")
                .font(VS.Typography.body(13))
                .foregroundStyle(VS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VS.Spacing.card)
        .glassCard(elevated: true)
    }

    private var requestsInbox: some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            VSSectionHeader(title: "Requests", subtitle: "Promote a request onto the public timeline.")
            VStack(spacing: 0) {
                ForEach(Array(voice.openRequests.enumerated()), id: \.element.id) { index, request in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(request.title)
                            .font(VS.Typography.heading(16, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)
                        if !request.detail.isEmpty {
                            Text(request.detail)
                                .font(VS.Typography.body(13))
                                .foregroundStyle(VS.Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("\(request.authorName) · \(request.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(VS.Typography.body(11))
                            .foregroundStyle(VS.Color.textTertiary)

                        HStack(spacing: 10) {
                            Button("Add to roadmap") {
                                Task { await voice.promote(request) }
                            }
                            .font(VS.Typography.body(13, weight: .semibold))
                            .foregroundStyle(VS.Color.navPill)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(VS.Color.accent, in: Capsule())

                            Button("Decline") {
                                Task { await voice.decline(request) }
                            }
                            .font(VS.Typography.body(13, weight: .semibold))
                            .foregroundStyle(VS.Color.error)
                        }
                    }
                    .padding(VS.Spacing.card)
                    if index < voice.openRequests.count - 1 {
                        Divider().overlay(VS.Color.divider)
                    }
                }
            }
            .glassCard(elevated: true)
        }
    }

    private var myRequestsSection: some View {
        VStack(alignment: .leading, spacing: VS.Spacing.stack) {
            VSSectionHeader(title: "Your requests")
            VStack(spacing: 0) {
                ForEach(Array(voice.myRequests.enumerated()), id: \.element.id) { index, request in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.title)
                            .font(VS.Typography.body(15, weight: .semibold))
                            .foregroundStyle(VS.Color.textPrimary)
                        Text("Waiting on review")
                            .font(VS.Typography.body(12))
                            .foregroundStyle(VS.Color.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(VS.Spacing.card)
                    if index < voice.myRequests.count - 1 {
                        Divider().overlay(VS.Color.divider)
                    }
                }
            }
            .glassCard(elevated: true)
        }
    }

    private func timelineSection(status: RoadmapStatus, items: [RoadmapItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(status.label)
                .font(VS.Typography.heading(17, weight: .bold))
                .foregroundStyle(VS.Color.textPrimary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    timelineRow(item, isLast: index == items.count - 1, status: status)
                }
            }
        }
    }

    private func timelineRow(_ item: RoadmapItem, isLast: Bool, status: RoadmapStatus) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(status == .released ? VS.Color.accent : VS.Color.navPill)
                    .overlay(
                        Circle().strokeBorder(VS.Color.accent, lineWidth: 2)
                    )
                    .frame(width: 14, height: 14)
                if !isLast {
                    Rectangle()
                        .fill(VS.Color.hairline)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(VS.Typography.heading(17, weight: .bold))
                            .foregroundStyle(VS.Color.textPrimary)
                        if !item.detail.isEmpty {
                            Text(item.detail)
                                .font(VS.Typography.body(13))
                                .foregroundStyle(VS.Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if status == .released, let releasedAt = item.releasedAt {
                            Text("Shipped \(releasedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(VS.Typography.body(11, weight: .medium))
                                .foregroundStyle(VS.Color.accent)
                        }
                    }
                    Spacer(minLength: 8)
                    if status != .released {
                        voteControl(item)
                    } else {
                        Text("\(item.voteCount)")
                            .font(VS.Typography.mono(12, weight: .semibold))
                            .foregroundStyle(VS.Color.textTertiary)
                    }
                }

                if voice.isModerator {
                    HStack(spacing: 8) {
                        ForEach(RoadmapStatus.allCases) { option in
                            VSSelectableChip(title: option.label, selected: item.status == option) {
                                Task { await voice.setStatus(item, status: option) }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : 22)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(status.label), \(item.voteCount) votes")
    }

    private func voteControl(_ item: RoadmapItem) -> some View {
        let voted = voice.votedItemIds.contains(item.id)
        return Button {
            guard let userId = auth.userId else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await voice.toggleVote(itemId: item.id, userId: userId) }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: voted ? "arrow.up.circle.fill" : "arrow.up.circle")
                    .font(.system(size: 22, weight: .semibold))
                Text("\(item.voteCount)")
                    .font(VS.Typography.mono(12, weight: .bold))
            }
            .foregroundStyle(voted ? VS.Color.navPill : VS.Color.textSecondary)
            .frame(width: 52, height: 52)
            .background(voted ? VS.Color.accent : VS.Color.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voted ? "Remove vote, \(item.voteCount)" : "Upvote, \(item.voteCount)")
    }
}
