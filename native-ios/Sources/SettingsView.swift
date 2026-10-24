import SwiftUI

struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @State private var cacheSize: Int64 = 0
    @State private var confirmClear = false
    var body: some View {
        @Bindable var settings = preferences
        Form {
            Section("Preferences") {
                Picker("Language", selection: $settings.language) { Text("Follow System").tag("system"); Text("简体中文").tag("zh-Hans"); Text("English").tag("en") }
                Picker("Appearance", selection: $settings.appearance) { Text("Follow System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
            }
            Section("Storage") {
                LabeledContent("Image cache", value: ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                Button("Clear image cache", role: .destructive) { confirmClear = true }.frame(minHeight: 44)
            }
            Section("About") {
                LabeledContent("App", value: "MangaBaka Native")
                LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                Link("MangaBaka website", destination: URL(string: "https://mangabaka.org")!)
                Link("Source code", destination: URL(string: "https://github.com/Ferrosophy/MangaBaka-App-ios/tree/feature/native-ios-m2")!)
                NavigationLink("Open-source licenses") {
                    ScrollView { Text("This app uses the MangaBaka public API. Original MangaBaka-App source and derived API mappings are licensed under Apache License 2.0. Copyright their respective contributors.\n\nLicensed under the Apache License, Version 2.0. You may obtain a copy at https://www.apache.org/licenses/LICENSE-2.0. Software is distributed on an AS IS basis, without warranties or conditions of any kind.").padding() }.navigationTitle("Open-source licenses")
                }
            }
        }
        .navigationTitle("Settings")
        .task { cacheSize = await ImageCache.shared.size() }
        .confirmationDialog("Clear image cache?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { Task { await ImageCache.shared.clear(); cacheSize = await ImageCache.shared.size() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your preferences will be kept. Images will download again when needed.") }
    }
}
