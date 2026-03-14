import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioEngine: AudioEngineManager
    var tracks: [Track]
    var markers: [SectionMarker]
    var sessionFolderURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var showSavedAlert = false

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

                Section("Sesión") {
                    Button(action: saveSession) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Guardar Sesión")
                        }
                    }
                    .disabled(sessionFolderURL == nil)
                }
            }
            .navigationTitle("Configuración")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
            .alert("Sesión guardada", isPresented: $showSavedAlert) {
                Button("OK") {}
            }
        }
    }

    private func saveSession() {
        guard let folderURL = sessionFolderURL else { return }

        let trackConfigs = tracks.map { track in
            SessionConfig.TrackConfig(
                filename: track.fileURL.lastPathComponent,
                volume: track.volume,
                pan: track.pan,
                isMuted: track.isMuted,
                isSolo: track.isSolo,
                eqGains: track.eqBands.map { $0.gain }
            )
        }

        let markerConfigs = markers.map {
            SessionConfig.MarkerConfig(name: $0.name, position: $0.position)
        }

        let config = SessionConfig(
            bpm: audioEngine.bpm,
            timeSignatureNumerator: audioEngine.timeSignatureNumerator,
            timeSignatureDenominator: audioEngine.timeSignatureDenominator,
            musicalKey: audioEngine.musicalKey,
            startOffset: audioEngine.startOffset,
            endTime: audioEngine.endTime,
            autoFadeAt: audioEngine.autoFadeAt,
            fadeDuration: audioEngine.fadeDuration,
            masterVolume: audioEngine.masterVolume,
            trackSettings: trackConfigs,
            markers: markerConfigs
        )

        config.save(to: folderURL)
        showSavedAlert = true
    }
}
