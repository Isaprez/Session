import SwiftUI

struct ContentView: View {
    @State private var sessions: [MusicSession] = []
    @State private var currentSession: MusicSession?
    @State private var showingImporter = false
    @StateObject private var audioEngine = AudioEngineManager()
    @State private var tracks: [Track] = []
    @State private var showSessionMenu = false
    @State private var showSettings = false
    @State private var showSessionSetup = false
    @State private var pendingSession: MusicSession?
    @State private var setupBpm: String = "120"
    @State private var setupNumerator: String = "4"
    @State private var setupDenominator: String = "4"
    @State private var setupKey: String = "C"

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if let session = currentSession {
                // Main mixer view
                mixerView(session: session)
            } else {
                emptyState
            }
        }
        .sheet(isPresented: $showingImporter) {
            FolderImporterView { url in
                importSession(from: url)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(audioEngine: audioEngine)
        }
        .sheet(isPresented: $showSessionSetup) {
            SessionSetupView(
                bpm: $setupBpm,
                numerator: $setupNumerator,
                denominator: $setupDenominator,
                key: $setupKey,
                sessionName: pendingSession?.name ?? "",
                onConfirm: {
                    guard var session = pendingSession else { return }
                    session.bpm = Double(setupBpm) ?? 120
                    session.timeSignatureNumerator = Int(setupNumerator) ?? 4
                    session.timeSignatureDenominator = Int(setupDenominator) ?? 4
                    session.musicalKey = setupKey
                    // Update in sessions array
                    if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                        sessions[idx] = session
                    }
                    switchSession(session)
                    showSessionSetup = false
                    pendingSession = nil
                },
                onCancel: {
                    // Load with defaults
                    if let session = pendingSession {
                        switchSession(session)
                    }
                    showSessionSetup = false
                    pendingSession = nil
                }
            )
            .presentationDetents([.height(300)])
        }
        .onAppear(perform: loadSavedSessions)
    }

    // MARK: - Mixer View (Main)

    private func mixerView(session: MusicSession) -> some View {
        VStack(spacing: 0) {
            // Transport bar
            TransportBar(
                isPlaying: audioEngine.isPlaying,
                currentTime: audioEngine.currentTime,
                duration: audioEngine.duration,
                onPlayPause: { audioEngine.togglePlayPause() },
                onStop: { audioEngine.stop() },
                onPrev: { switchToPrevSession() },
                onNext: { switchToNextSession() },
                isFading: audioEngine.isFading,
                fadeMode: audioEngine.fadeMode,
                onFadeTap: { audioEngine.toggleFade() },
                onSettingsTap: { showSettings = true },
                startOffset: $audioEngine.startOffset,
                endTime: $audioEngine.endTime,
                autoFadeAt: $audioEngine.autoFadeAt,
                maxDuration: audioEngine.duration,
                sessionMenuContent: AnyView(sessionMenuItems),
                sessionName: session.name,
                masterLevel: audioEngine.masterLevel,
                levelHistory: audioEngine.levelHistory,
                onSeek: { time in audioEngine.seekTo(time) },
                bpm: $audioEngine.bpm,
                originalBpm: audioEngine.originalBpm,
                musicalKey: $audioEngine.musicalKey,
                originalKey: audioEngine.originalKey,
                timeSignatureNumerator: audioEngine.timeSignatureNumerator,
                timeSignatureDenominator: audioEngine.timeSignatureDenominator
            )

            Divider()

            // Master + Special tracks (fixed) + Regular tracks (scroll)
            HStack(spacing: 0) {
                // Master fader - fixed on the left
                MasterStripView(
                    volume: Binding(
                        get: { audioEngine.masterVolume },
                        set: { audioEngine.masterVolume = $0 }
                    ),
                    level: audioEngine.masterLevel
                )

                Divider()

                // All tracks - horizontal scroll (special first)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(sortedTrackIndices, id: \.self) { index in
                            TrackStripView(
                                track: $tracks[index],
                                level: audioEngine.trackLevels[tracks[index].id] ?? 0,
                                onVolumeChange: { vol in
                                    audioEngine.setVolume(vol, for: tracks[index].id)
                                    audioEngine.applySoloState(tracks: tracks)
                                },
                                onMuteToggle: {
                                    audioEngine.applySoloState(tracks: tracks)
                                },
                                onSoloToggle: {
                                    audioEngine.applySoloState(tracks: tracks)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Session Menu Items

    @ViewBuilder
    private var sessionMenuItems: some View {
        Section("Sesiones") {
            ForEach(sessions) { s in
                Button(action: { switchSession(s) }) {
                    Label(
                        s.name,
                        systemImage: s.id == currentSession?.id ? "checkmark.circle.fill" : "music.note.list"
                    )
                }
            }
        }
        Divider()
        Button(action: { showingImporter = true }) {
            Label("Importar Carpeta", systemImage: "folder.badge.plus")
        }
        if currentSession != nil {
            Divider()
            Button(role: .destructive, action: deleteCurrentSession) {
                Label("Eliminar Sesión", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No hay sesiones")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Importa una carpeta con los\nmultitracks de tu canción")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(action: { showingImporter = true }) {
                Label("Importar Carpeta", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
    }

    // MARK: - Track Filtering

    private var sortedTrackIndices: [Int] {
        let special = tracks.indices.filter { tracks[$0].isSpecial }
        let regular = tracks.indices.filter { !tracks[$0].isSpecial }
        return special + regular
    }

    // MARK: - Session Navigation

    private var currentSessionIndex: Int? {
        guard let current = currentSession else { return nil }
        return sessions.firstIndex(where: { $0.id == current.id })
    }

    private func switchToPrevSession() {
        guard let index = currentSessionIndex, sessions.count > 1 else { return }
        let prevIndex = index > 0 ? index - 1 : sessions.count - 1
        switchSession(sessions[prevIndex])
    }

    private func switchToNextSession() {
        guard let index = currentSessionIndex, sessions.count > 1 else { return }
        let nextIndex = index < sessions.count - 1 ? index + 1 : 0
        switchSession(sessions[nextIndex])
    }

    // MARK: - Session Management

    private func switchSession(_ session: MusicSession) {
        audioEngine.stop()
        currentSession = session
        tracks = session.tracks
        configureAudioSession()
        audioEngine.loadSession(session)
        audioEngine.loadSessionMetadata(session)
    }

    private func importSession(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsURL.appendingPathComponent(url.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)

            if let session = MusicSession.load(from: destinationURL) {
                sessions.append(session)
                pendingSession = session
                setupBpm = "120"
                setupNumerator = "4"
                setupDenominator = "4"
                setupKey = "C"
                showSessionSetup = true
            }
        } catch {
            print("Error importing session: \(error)")
        }
    }

    private func loadSavedSessions() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        sessions = contents.compactMap { url -> MusicSession? in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            guard isDir.boolValue else { return nil }
            return MusicSession.load(from: url)
        }

        // Auto-load the first session
        if let first = sessions.first {
            switchSession(first)
        }
    }

    private func deleteCurrentSession() {
        guard let session = currentSession else { return }
        audioEngine.stop()
        try? FileManager.default.removeItem(at: session.folderURL)
        sessions.removeAll { $0.id == session.id }
        currentSession = nil
        tracks = []
        if let first = sessions.first {
            switchSession(first)
        }
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Error configuring audio session: \(error)")
        }
    }
}

import AVFoundation

// MARK: - Session Setup Dialog

struct SessionSetupView: View {
    @Binding var bpm: String
    @Binding var numerator: String
    @Binding var denominator: String
    @Binding var key: String
    let sessionName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let keys = AudioEngineManager.allKeys

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text(sessionName)
                    .font(.headline)
                    .foregroundColor(.secondary)

                // BPM
                HStack {
                    Text("BPM")
                        .font(.subheadline.bold())
                        .frame(width: 80, alignment: .leading)
                    TextField("120", text: $bpm)
                        .keyboardType(.numberPad)
                        .font(.system(.title3, design: .monospaced))
                        .frame(width: 80)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }

                // Time Signature
                HStack {
                    Text("Compás")
                        .font(.subheadline.bold())
                        .frame(width: 80, alignment: .leading)
                    TextField("4", text: $numerator)
                        .keyboardType(.numberPad)
                        .font(.system(.title3, design: .monospaced))
                        .frame(width: 40)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    Text("/")
                        .font(.title3)
                    TextField("4", text: $denominator)
                        .keyboardType(.numberPad)
                        .font(.system(.title3, design: .monospaced))
                        .frame(width: 40)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }

                // Key
                HStack {
                    Text("Tono")
                        .font(.subheadline.bold())
                        .frame(width: 80, alignment: .leading)
                    Picker("Tono", selection: $key) {
                        ForEach(keys, id: \.self) { k in
                            Text(k).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Configurar Sesión")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Omitir") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Confirmar") { onConfirm() }
                        .bold()
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
