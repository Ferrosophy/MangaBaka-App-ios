import SwiftUI

struct PATSignInView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var failure: String?
    @State private var submitting = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Create a personal access token in your MangaBaka account settings, then enter it here.")
                    Link("Open MangaBaka account settings", destination: URL(string: "https://mangabaka.org/my/settings/api-and-apps")!)
                    Text("Choose Personal access tokens (PAT) for API, then New token.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Personal access token") {
                    SecureField("mb-…", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("pat-input")
                    Text("The token is stored only in this device’s Keychain. It is never included in backups.").font(.footnote).foregroundStyle(.secondary)
                    Text("A PAT grants full account access. You can revoke it on the MangaBaka website.").font(.footnote).foregroundStyle(.secondary)
                }
                if let failure { Section { Text(LocalizedStringKey(failure)).foregroundStyle(.orange).accessibilityIdentifier("pat-error") } }
                Section {
                    Button { connect() } label: { HStack { if submitting { ProgressView() }; Text("Connect account") } }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting).accessibilityIdentifier("pat-connect")
                }
            }.navigationTitle("Sign in with PAT").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { token = ""; dismiss() }.disabled(submitting) } }
                .interactiveDismissDisabled(submitting)
                .onDisappear { token = "" }
        }
    }
    private func connect() {
        submitting = true; failure = nil
        Task { @MainActor in
            do { try await auth.signIn(personalAccessToken: token); token = ""; dismiss() }
            catch { failure = (error as? AccountError)?.errorDescription ?? "Connection failed. Check your network and try again." }
            submitting = false
        }
    }
}
