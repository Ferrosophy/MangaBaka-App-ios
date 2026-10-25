import SwiftUI
import Observation

@MainActor @Observable final class DescriptionTranslationModel {
    var translated: String?
    var failure: String?
    var loading = false
    var showingTranslation = false
    private var generation = UUID()
    private var task: Task<Void, Never>?
    let service: any TextTranslating
    init(service: any TextTranslating = TranslationService.shared) { self.service = service }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; loading = false }
    func clear() { cancel(); translated = nil; failure = nil; showingTranslation = false }
    func start(_ text: String, provider: TranslationProvider, target: String, credentials: TranslationCredentials) {
        cancel(); let token = generation; failure = nil; loading = true
        task = Task {
            do {
                let result = try await service.translate(text, provider: provider, target: target, credentials: credentials)
                guard !Task.isCancelled, generation == token else { return }
                translated = result; showingTranslation = true; loading = false
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                failure = (error as? TranslationFailure)?.errorDescription ?? "Translation request failed. Try again later."
                loading = false
            }
        }
    }
}
struct TranslatedDescription: View {
    let text: String
    @Environment(Preferences.self) private var preferences
    @AppStorage("translation-provider") private var providerName = "google"
    @AppStorage("translation-target") private var targetName = "auto"
    @State private var model = DescriptionTranslationModel()
    @State private var expanded = false
    @State private var copied = false
    @State private var settings = false
    private var provider: TranslationProvider { TranslationProvider(rawValue: providerName) ?? .google }
    private var target: String { targetName == "auto" ? (preferences.locale.identifier.hasPrefix("zh") ? "zh-Hans" : "en") : targetName }
    private var identity: String { text + providerName + target }
    private var visibleText: String { model.showingTranslation ? model.translated ?? text : text }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Description").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                if model.loading {
                    ProgressView(); Button("Cancel") { model.cancel() }
                } else {
                    Button("Translate", systemImage: "translate") { translate() }.accessibilityIdentifier("translate-description")
                }
            }
            if model.translated != nil {
                Picker("Description language", selection: $model.showingTranslation) { Text("Original text").tag(false); Text("Translation").tag(true) }.pickerStyle(.segmented)
            }
            Text((try? AttributedString(markdown: visibleText, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(visibleText))
                .lineSpacing(6).lineLimit(expanded ? nil : 8).textSelection(.enabled)
            if model.showingTranslation { Text("\(preferences.text("Translated by")) \(preferences.text(provider.title))").font(.caption).foregroundStyle(.secondary) }
            if let failure = model.failure {
                Text(preferences.text(failure)).font(.footnote).foregroundStyle(.orange)
                HStack { Button("Retry") { translate() }; Button("Translation settings") { settings = true } }
            }
            HStack {
                Button(LocalizedStringKey(expanded ? "Show less" : "Show more")) { expanded.toggle() }
                Spacer()
                Button { UIPasteboard.general.string = visibleText; copied = true } label: { Label(LocalizedStringKey(copied ? "Copied" : "Copy description"), systemImage: "doc.on.doc") }
            }.frame(minHeight: 44)
        }.onChange(of: identity) { model.clear(); copied = false }
            .onDisappear { model.cancel() }
            .sheet(isPresented: $settings) { NavigationStack { TranslationSettingsView() }.environment(preferences) }
    }
    private func translate() {
        do {
            let credentials = try TranslationVault().load(provider)
            guard credentials.valid(for: provider) else { model.failure = TranslationFailure.missing.errorDescription; settings = true; return }
            let plain = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))).map { String($0.characters) } ?? text
            model.start(plain, provider: provider, target: target, credentials: credentials)
        } catch { model.failure = TranslationFailure.storage.errorDescription }
    }
}
struct TranslationSettingsView: View {
    @AppStorage("translation-provider") private var providerName = "google"
    @AppStorage("translation-target") private var targetName = "auto"
    @State private var credentials = TranslationCredentials()
    @State private var message: String?
    @State private var testing = false
    @State private var deleting = false
    @State private var request: Task<Void, Never>?
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    private var provider: TranslationProvider { TranslationProvider(rawValue: providerName) ?? .google }
    var body: some View {
        Form {
            Section {
                Picker("Translation service", selection: $providerName) { ForEach(TranslationProvider.allCases) { Text(LocalizedStringKey($0.title)).tag($0.rawValue) } }
                Picker("Target language", selection: $targetName) { Text("Follow app language").tag("auto"); Text("简体中文").tag("zh-Hans"); Text("English").tag("en") }
            }
            Section("Service credentials") {
                SecureField(LocalizedStringKey(provider == .volcano ? "Access Key ID" : "API Key"), text: $credentials.key).textInputAutocapitalization(.never).autocorrectionDisabled()
                if provider == .volcano { SecureField("Secret Access Key", text: $credentials.secret).textInputAutocapitalization(.never).autocorrectionDisabled() }
                if provider == .bing { TextField("Resource region (if required)", text: $credentials.region).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Button("Save credentials") {
                    do {
                        guard credentials.valid(for: provider) else { message = TranslationFailure.missing.errorDescription; return }
                        try TranslationVault().save(credentials, for: provider); message = "Credentials saved in Keychain."
                    } catch { message = TranslationFailure.storage.errorDescription }
                }.disabled(testing)
                Button("Test connection") { test() }.disabled(testing || !credentials.valid(for: provider))
                Button("Delete credentials", role: .destructive) { deleting = true }.disabled(testing)
                if testing { HStack { ProgressView(); Button("Cancel") { request?.cancel(); testing = false } } }
            }
            Section {
                Text("Translation uses your own service account and may incur charges. Only the description is sent when you tap Translate. Credentials stay in Keychain and are excluded from backups.").font(.footnote).foregroundStyle(.secondary)
                if let message { Text(preferences.text(message)).font(.footnote).accessibilityIdentifier("translation-status") }
                Link("Google translation documentation", destination: URL(string: "https://cloud.google.com/translate/docs/reference/rest/v2/translate")!)
                Link("Volcengine translation documentation", destination: URL(string: "https://www.volcengine.com/docs/4640/65067")!)
                Link("Microsoft translation documentation", destination: URL(string: "https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/v3/translate")!)
            }
        }.navigationTitle("Translation settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { load() }.onChange(of: providerName) { request?.cancel(); testing = false; load() }
            .onDisappear { request?.cancel(); credentials = TranslationCredentials() }
            .confirmationDialog("Delete translation credentials?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete credentials", role: .destructive) { do { try TranslationVault().remove(provider); credentials = TranslationCredentials(); message = "Credentials deleted." } catch { message = TranslationFailure.storage.errorDescription } }
            }
    }
    private func load() { message = nil; do { credentials = try TranslationVault().load(provider) } catch { credentials = TranslationCredentials(); message = TranslationFailure.storage.errorDescription } }
    private func test() {
        testing = true; message = nil
        let selected = provider; let value = credentials
        let target = targetName == "auto" ? (preferences.locale.identifier.hasPrefix("zh") ? "zh-Hans" : "en") : targetName
        request = Task {
            do {
                try await TranslationService.shared.checkConnection(provider: selected, target: target, credentials: value)
                if !Task.isCancelled, selected == provider { message = "Translation connection succeeded." }
            } catch { if !Task.isCancelled, selected == provider { message = (error as? TranslationFailure)?.errorDescription ?? "Translation request failed. Try again later." } }
            if !Task.isCancelled, selected == provider { testing = false }
        }
    }
}
