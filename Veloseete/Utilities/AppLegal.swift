import Foundation
import SwiftUI

/// In-app legal documents + public URLs for App Store Connect later.
enum AppLegal {
    /// Update these when you host public pages (required by App Store Connect).
    static let privacyPolicyURL = URL(string: "https://veloseete.com/privacy")!
    static let termsOfUseURL = URL(string: "https://veloseete.com/terms")!

    enum Document: String, Identifiable {
        case privacy
        case terms

        var id: String { rawValue }

        var title: String {
            switch self {
            case .privacy: return "Privacy Policy"
            case .terms: return "Terms of Use"
            }
        }

        var resourceName: String {
            switch self {
            case .privacy: return "PrivacyPolicy"
            case .terms: return "TermsOfUse"
            }
        }

        var publicURL: URL {
            switch self {
            case .privacy: return AppLegal.privacyPolicyURL
            case .terms: return AppLegal.termsOfUseURL
            }
        }

        var markdown: String {
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                return "# \(title)\n\nDocument missing from the app bundle."
            }
            return text
        }
    }
}

struct LegalDocumentView: View {
    let document: AppLegal.Document
    @Environment(\.dismiss) private var dismiss

    private var attributedBody: AttributedString {
        (try? AttributedString(
            markdown: document.markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(document.markdown)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(attributedBody)
                    .font(VS.Typography.body(14))
                    .foregroundStyle(VS.Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .textSelection(.enabled)
            }
            .veloseetePage()
            .navigationTitle(document.title)
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
}

struct LegalLinksRow: View {
    var onOpen: (AppLegal.Document) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button("Privacy") { onOpen(.privacy) }
            Text("·").foregroundStyle(VS.Color.textTertiary)
            Button("Terms") { onOpen(.terms) }
        }
        .font(VS.Typography.body(12, weight: .medium))
        .foregroundStyle(VS.Color.accent)
    }
}
