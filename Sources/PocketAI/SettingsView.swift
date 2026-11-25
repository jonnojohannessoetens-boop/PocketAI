import SwiftUI

struct SettingsView: View {
    @Environment(LLMManager.self) private var llm
    @AppStorage("pocketai.contextSize") private var contextSize = 2048
    @AppStorage("pocketai.useGPU") private var useGPU = true
    @AppStorage("pocketai.systemPrompt") private var systemPrompt = "Je bent een behulpzame assistent. Antwoord in de taal van de gebruiker."
    @AppStorage("pocketai.temperature") private var temperature = 0.7
    @AppStorage("pocketai.topP") private var topP = 0.9
    @AppStorage("pocketai.useRAG") private var useRAG = false

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
                LabeledContent("Temperatuur", value: temperature.formatted(.number.precision(.fractionLength(1))))
                Slider(value: $temperature, in: 0...1.5, step: 0.1)
                LabeledContent("Top-P", value: topP.formatted(.number.precision(.fractionLength(2))))
                Slider(value: $topP, in: 0.1...1, step: 0.05)
                Text("Context- en GPU-wijzigingen herladen het actieve model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Systeemprompt") {
                TextEditor(text: $systemPrompt).frame(minHeight: 90)
            }
            Section("Documentchat (RAG)") {
                Toggle("Lokale documenten gebruiken", isOn: $useRAG)
                Text("TXT- en PDF-documenten worden lokaal doorzocht; relevante fragmenten worden aan de chatprompt toegevoegd.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Geheugen") {
                LabeledContent("Modelbestanden", value: "Documents/Models")
                LabeledContent("Mmap", value: "Ingeschakeld indien ondersteund")
                Text("Geen verhoogde geheugenrechten. De geheugenschatting is indicatief en garandeert niet dat iOS een model kan laden.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if llm.activeModelURL != nil {
                Section { Button("Model vrijgeven", role: .destructive) { Task { await llm.unloadModel() } } }
            }
            Section("Over JJS") {
                LabeledContent("App", value: "JJS")
                LabeledContent("Inference", value: "llama.cpp / SwiftLlama")
            }
        }
        .navigationTitle("Instellingen")
        .onChange(of: contextSize) { _, value in applyConfiguration(context: value, gpu: useGPU) }
        .onChange(of: useGPU) { _, value in applyConfiguration(context: contextSize, gpu: value) }
    }

    private func applyConfiguration(context: Int, gpu: Bool) {
        Task { await llm.configure(contextSize: UInt32(context), useGPU: gpu) }
    }
}
