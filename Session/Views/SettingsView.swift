import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, paneo, ecualizador

    var label: String {
        switch self {
        case .general: return "General"
        case .paneo: return "Paneo"
        case .ecualizador: return "EQ"
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .paneo: return "speaker.wave.2"
        case .ecualizador: return "equal"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var audioEngine: AudioEngineManager
    @Binding var tracks: [Track]
    var markers: [SectionMarker]
    var sessionFolderURL: URL?
    var sessions: [MusicSession] = []
    @Environment(\.dismiss) private var dismiss
    @State private var showSavedAlert = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var isZipping = false
    @State private var isZippingAll = false
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationView {
            HStack(spacing: 0) {
                // Sidebar
                VStack(spacing: 2) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 14))
                                    .frame(width: 20)
                                Text(tab.label)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                if tab == .paneo && tracks.contains(where: { $0.pan != 0 }) {
                                    Circle().fill(.orange).frame(width: 6, height: 6)
                                }
                                if tab == .ecualizador && tracks.contains(where: { t in t.eqBands.contains(where: { $0.gain != 0 }) }) {
                                    Circle().fill(.orange).frame(width: 6, height: 6)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            .foregroundColor(selectedTab == tab ? .accentColor : .primary)
                            .cornerRadius(8)
                        }
                    }
                    Spacer()
                }
                .frame(width: 130)
                .padding(.top, 8)
                .padding(.horizontal, 4)
                .background(Color(.systemGroupedBackground))

                Divider()

                // Detail
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                        .onDisappear {
                            try? FileManager.default.removeItem(at: url)
                            shareURL = nil
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .general:
            generalDetail
        case .paneo:
            paneoDetail
        case .ecualizador:
            eqDetail
        }
    }

    // MARK: - General

    private var generalDetail: some View {
        List {
            Section("Fade") {
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

            Section("Grilla") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Offset de Grilla")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.2f s", audioEngine.gridOffset))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { audioEngine.gridOffset },
                        set: { audioEngine.gridOffset = $0 }
                    ), in: 0...5, step: 0.01)
                    .tint(.accentColor)

                    Text("Ajusta para alinear las líneas de compás con el audio")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                Button {
                    audioEngine.autoDetectGridOffset()
                } label: {
                    HStack {
                        Label("Detectar Automáticamente", systemImage: "wand.and.stars")
                            .font(.subheadline)
                        Spacer()
                        if audioEngine.isDetectingGrid {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if audioEngine.gridDetected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .disabled(audioEngine.isDetectingGrid)
            }

            Section("Transición") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modo de Transición")
                        .font(.subheadline)
                    Picker("Modo", selection: Binding(
                        get: { audioEngine.transitionMode },
                        set: { audioEngine.transitionMode = $0 }
                    )) {
                        ForEach(TransitionMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(audioEngine.transitionMode.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Duración Transición")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(audioEngine.transitionDuration)) s")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { audioEngine.transitionDuration },
                        set: { audioEngine.transitionDuration = $0 }
                    ), in: 0...30, step: 1)
                    .tint(.accentColor)

                    Text("Aplica a Crossfade y Overlap")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Sesión") {
                Button(action: saveSession) {
                    Label("Guardar Pista Actual", systemImage: "square.and.arrow.down")
                }
                .disabled(sessionFolderURL == nil)

                Button(action: shareCurrentSession) {
                    HStack {
                        Label("Compartir Pista Actual", systemImage: "square.and.arrow.up")
                        if isZipping {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(sessionFolderURL == nil || isZipping || isZippingAll)

                Button(action: shareAllSessions) {
                    HStack {
                        Label("Compartir Sesión Completa", systemImage: "square.and.arrow.up.on.square")
                        if isZippingAll {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(sessions.isEmpty || isZipping || isZippingAll)
            }
        }
    }

    // MARK: - Paneo

    private var paneoDetail: some View {
        List {
            ForEach(tracks.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    HStack {
                        Text(tracks[index].displayName)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(width: 60, alignment: .leading)

                        Text("L")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Slider(value: $tracks[index].pan, in: -1...1, step: 0.1) { _ in
                            audioEngine.setPan(tracks[index].pan, for: tracks[index].id)
                        }
                        .tint(tracks[index].pan == 0 ? .gray : tracks[index].pan < 0 ? .blue : .orange)

                        Text("R")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(panLabel(tracks[index].pan))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - EQ

    private var eqDetail: some View {
        List {
            ForEach(tracks.indices, id: \.self) { index in
                NavigationLink {
                    EQEditorView(
                        track: $tracks[index],
                        onEQChange: { bands in
                            audioEngine.updateEQ(for: tracks[index].id, bands: bands)
                        }
                    )
                } label: {
                    HStack {
                        Text(tracks[index].displayName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        if tracks[index].eqBands.contains(where: { $0.gain != 0 }) {
                            Text("Modificado")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func panLabel(_ pan: Float) -> String {
        if pan == 0 { return "C" }
        let pct = Int(abs(pan) * 100)
        return pan < 0 ? "L\(pct)" : "R\(pct)"
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
            gridOffset: audioEngine.gridOffset,
            transitionMode: audioEngine.transitionMode.rawValue,
            transitionDuration: audioEngine.transitionDuration,
            masterVolume: audioEngine.masterVolume,
            trackSettings: trackConfigs,
            markers: markerConfigs
        )

        config.save(to: folderURL)
        showSavedAlert = true
    }

    private func shareCurrentSession() {
        guard let folderURL = sessionFolderURL else { return }
        saveSession()

        isZipping = true
        DispatchQueue.global(qos: .userInitiated).async {
            let folderName = folderURL.lastPathComponent
            let tempDir = FileManager.default.temporaryDirectory
            let zipURL = tempDir.appendingPathComponent("\(folderName).zip")
            try? FileManager.default.removeItem(at: zipURL)

            let coordinator = NSFileCoordinator()
            var error: NSError?
            coordinator.coordinate(readingItemAt: folderURL, options: .forUploading, error: &error) { tempURL in
                try? FileManager.default.copyItem(at: tempURL, to: zipURL)
            }

            DispatchQueue.main.async {
                isZipping = false
                if FileManager.default.fileExists(atPath: zipURL.path) {
                    shareURL = zipURL
                    showShareSheet = true
                }
            }
        }
    }

    private func shareAllSessions() {
        guard !sessions.isEmpty else { return }
        saveSession()

        isZippingAll = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let tempDir = fm.temporaryDirectory
            let containerName = "Session"
            let containerURL = tempDir.appendingPathComponent(containerName)

            // Clean up previous temp folder
            try? fm.removeItem(at: containerURL)
            try? fm.createDirectory(at: containerURL, withIntermediateDirectories: true)

            // Copy each session folder into the container
            for session in sessions {
                let destURL = containerURL.appendingPathComponent(session.folderURL.lastPathComponent)
                try? fm.copyItem(at: session.folderURL, to: destURL)
            }

            // Zip the container folder
            let zipURL = tempDir.appendingPathComponent("\(containerName).zip")
            try? fm.removeItem(at: zipURL)

            let coordinator = NSFileCoordinator()
            var error: NSError?
            coordinator.coordinate(readingItemAt: containerURL, options: .forUploading, error: &error) { tempURL in
                try? fm.copyItem(at: tempURL, to: zipURL)
            }

            // Clean up temp container
            try? fm.removeItem(at: containerURL)

            DispatchQueue.main.async {
                isZippingAll = false
                if fm.fileExists(atPath: zipURL.path) {
                    shareURL = zipURL
                    showShareSheet = true
                }
            }
        }
    }
}

// MARK: - EQ Editor

struct EQEditorView: View {
    @Binding var track: Track
    let onEQChange: ([EQBand]) -> Void

    var body: some View {
        VStack(spacing: 20) {
            ForEach(track.eqBands.indices, id: \.self) { index in
                HStack {
                    Text(track.eqBands[index].label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)

                    Slider(value: $track.eqBands[index].gain, in: -12...12, step: 0.5) { _ in
                        onEQChange(track.eqBands)
                    }
                    .tint(track.eqBands[index].gain >= 0 ? .green : .red)

                    Text(String(format: "%+.1f dB", track.eqBands[index].gain))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }

            Button(action: {
                track.eqBands = EQBand.defaultBands
                onEQChange(track.eqBands)
            }) {
                Label("Resetear EQ", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(8)
            }
        }
        .padding()
        .navigationTitle(track.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - UIKit Share Sheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
