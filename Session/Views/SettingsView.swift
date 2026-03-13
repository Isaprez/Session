import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioEngine: AudioEngineManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("General") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Duración Fade In/Out")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(audioEngine.fadeDuration)) s")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { audioEngine.fadeDuration },
                            set: { audioEngine.fadeDuration = $0 }
                        ), in: 0...30, step: 1)
                        .tint(.accentColor)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Configuración")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}
