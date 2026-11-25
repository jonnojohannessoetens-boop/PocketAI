import SwiftUI

struct SettingsView: View {
    @Environment(LLMManager.self) private var llm
    @AppStorage("pocketai.contextSize") private var contextSize = 2048
    @AppStorage("pocketai.useGPU") private var useGPU = true

    var body: some View {
        Form {
            Section("Inferentie") {
                Picker("Contextgrootte", selection: $contextSize) {
                    Text("1.024 tokens").tag(1024)
                    Text("2.048 tokens").tag(2048)
                    Text("4.096 tokens").tag(4096)
                    Text("8.192 tokens").tag(8192)
                }
                Toggle("Metal GPU-versnelling", isOn: $useGPU)
                Text("Wijzigingen aan de context- en GPU-instellingen zijn van toepassing wanneer de engine-configuratie opnieuw wordt aangemaakt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Geheugen") {
                LabeledContent("Mmap", value: "Ingeschakeld indien ondersteund")
                Text("PocketAI vraagt geen verhoogde geheugenrechten aan. Kies een model dat past bij het beschikbare geheugen van je apparaat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if llm.activeModelURL != nil {
                Section {
                    Button("Model vrijgeven", role: .destructive) {
                        Task { await llm.unloadModel() }
                    }
                }
            }
            Section("Over PocketAI") {
                LabeledContent("Versie", value: "MVP")
                LabeledContent("Inference", value: "llama.cpp / SwiftLlama")
            }
        }
        .navigationTitle("Instellingen")
    }
}
