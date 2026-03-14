import SwiftUI

struct ContentView: View {
    @State private var sessions: [MusicSession] = []
    @State private var currentSession: MusicSession?
    @State private var showingImporter = false
    @StateObject private var audioEngine = AudioEngineManager()
    @StateObject private var secondaryEngine = AudioEngineManager()
    @State private var isTransitioning = false
    @State private var isArmed = false
    @State private var tracks: [Track] = []
    @State private var showSessionMenu = false
    @State private var showSettings = false
    @State private var showSessionSetup = false
    @State private var pendingSession: MusicSession?
    @State private var showTimeMenu = false
    @State private var showBpmMenu = false
    @State private var showKeyMenu = false
    @State private var markers: [SectionMarker] = []
    @State private var isEditMode = false
    @State private var sessionTransitionModes: [UUID: TransitionMode] = [:]
    @State private var showSectionPicker = false
    @State private var pendingMarkerPosition: Double = 0
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
                    .ignoresSafeArea(edges: .bottom)
            } else {
                emptyState
            }
        }
        .sheet(isPresented: $showingImporter) {
            FolderImporterView { url in
                importSession(from: url)
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            if let sid = currentSession?.id {
                sessionTransitionModes[sid] = audioEngine.transitionMode
            }
        }) {
            SettingsView(
                audioEngine: audioEngine,
                tracks: $tracks,
                markers: markers,
                sessionFolderURL: currentSession?.folderURL,
                sessions: sessions
            )
        }
        .sheet(isPresented: $showSessionSetup) {
            SessionSetupView(
                bpm: $setupBpm,
                numerator: $setupNumerator,
                denominator: $setupDenominator,
                key: $setupKey,
                sessionName: pendingSession?.name ?? "",
                onConfirm: { newName in
                    guard var session = pendingSession else { return }
                    session.bpm = Double(setupBpm) ?? 120
                    session.timeSignatureNumerator = Int(setupNumerator) ?? 4
                    session.timeSignatureDenominator = Int(setupDenominator) ?? 4
                    session.musicalKey = setupKey
                    // Rename folder if name changed
                    if !newName.isEmpty && newName != session.folderURL.lastPathComponent {
                        let parentDir = session.folderURL.deletingLastPathComponent()
                        let newFolderURL = parentDir.appendingPathComponent(newName)
                        if !FileManager.default.fileExists(atPath: newFolderURL.path) {
                            try? FileManager.default.moveItem(at: session.folderURL, to: newFolderURL)
                            session.folderURL = newFolderURL
                            session.name = newName
                                .replacingOccurrences(of: "_", with: " ")
                                .replacingOccurrences(of: "-", with: " ")
                            // Update track file URLs
                            session.tracks = session.tracks.map { track in
                                var t = track
                                t.fileURL = newFolderURL.appendingPathComponent(track.fileURL.lastPathComponent)
                                return t
                            }
                        }
                    }
                    // Save initial config
                    var config = SessionConfig.defaultConfig()
                    config.bpm = session.bpm
                    config.timeSignatureNumerator = session.timeSignatureNumerator
                    config.timeSignatureDenominator = session.timeSignatureDenominator
                    config.musicalKey = session.musicalKey
                    config.save(to: session.folderURL)
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
        .onAppear {
            loadSavedSessions()
            audioEngine.onTrackEnd = { [self] mode in
                handleTransition(mode: mode)
            }
        }
    }

    // MARK: - Mixer View (Main)

    private func mixerView(session: MusicSession) -> some View {
        ZStack {
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
                    isRepeatingSection: $audioEngine.isRepeatingSection,
                    onRepeatSection: { activateRepeatSection() },
                    onSettingsTap: { showSettings = true },
                    startOffset: $audioEngine.startOffset,
                    endTime: $audioEngine.endTime,
                    autoFadeAt: $audioEngine.autoFadeAt,
                    maxDuration: audioEngine.duration,
                    onSessionMenuTap: {
                        showTimeMenu = false
                        showBpmMenu = false
                        showKeyMenu = false
                        showSessionMenu.toggle()
                    },
                    sessionName: session.name,
                    masterLevel: audioEngine.masterLevel,
                    levelHistory: audioEngine.levelHistory,
                    levelHistoryZoom1: audioEngine.levelHistoryZoom1,
                    levelHistoryZoom2: audioEngine.levelHistoryZoom2,
                    isGeneratingWaveform: audioEngine.isGeneratingWaveform,
                    onSeek: { time in audioEngine.seekTo(time) },
                    bpm: $audioEngine.bpm,
                    originalBpm: audioEngine.originalBpm,
                    musicalKey: $audioEngine.musicalKey,
                    originalKey: audioEngine.originalKey,
                    timeSignatureNumerator: audioEngine.timeSignatureNumerator,
                    timeSignatureDenominator: audioEngine.timeSignatureDenominator,
                    gridOffset: audioEngine.gridOffset,
                    showSessionMenu: $showSessionMenu,
                    showTimeMenu: $showTimeMenu,
                    showBpmMenu: $showBpmMenu,
                    showKeyMenu: $showKeyMenu,
                    markers: $markers,
                    isEditMode: $isEditMode,
                    onMarkerAdd: { position in
                        pendingMarkerPosition = position
                        showSectionPicker = true
                    },
                    onSaveMarkers: {
                        guard let folderURL = currentSession?.folderURL else { return }
                        SessionConfig.saveMarkers(markers, to: folderURL)
                    }
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

            // Popover overlays
            if showTimeMenu || showBpmMenu || showKeyMenu || showSessionMenu {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showTimeMenu = false
                        showBpmMenu = false
                        showKeyMenu = false
                        showSessionMenu = false
                    }

                // Session menu popover (left side)
                if showSessionMenu {
                    SessionMenuPopover(
                        sessions: $sessions,
                        currentSession: currentSession,
                        sessionTransitionModes: sessionTransitionModes,
                        onSelect: { s in
                            showSessionMenu = false
                            switchSession(s)
                        },
                        onDelete: { s in
                            showSessionMenu = false
                            deleteSession(s)
                        },
                        onTransitionChange: { s, mode in
                            sessionTransitionModes[s.id] = mode
                            if var config = SessionConfig.load(from: s.folderURL) {
                                config.transitionMode = mode.rawValue
                                config.save(to: s.folderURL)
                            }
                            if s.id == currentSession?.id {
                                audioEngine.transitionMode = mode
                            }
                        },
                        onReorder: { _ in },
                        onImport: {
                            showSessionMenu = false
                            showingImporter = true
                        },
                        onDismiss: { showSessionMenu = false }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 8)
                    .padding(.top, 70)
                    .allowsHitTesting(true)
                }

                VStack {
                    HStack {
                        Spacer()
                        if showTimeMenu {
                            TimePopover(
                                startOffset: $audioEngine.startOffset,
                                endTime: $audioEngine.endTime,
                                autoFadeAt: $audioEngine.autoFadeAt,
                                duration: audioEngine.duration,
                                onDismiss: { showTimeMenu = false }
                            )
                        }
                        if showBpmMenu {
                            BpmPopover(
                                bpm: $audioEngine.bpm,
                                originalBpm: audioEngine.originalBpm,
                                timeSignatureNumerator: audioEngine.timeSignatureNumerator,
                                timeSignatureDenominator: audioEngine.timeSignatureDenominator,
                                onDismiss: { showBpmMenu = false }
                            )
                        }
                        if showKeyMenu {
                            KeyPopover(
                                musicalKey: $audioEngine.musicalKey,
                                originalKey: audioEngine.originalKey,
                                onDismiss: { showKeyMenu = false }
                            )
                        }
                        Spacer().frame(width: 80)
                    }
                    .padding(.top, 70)
                    Spacer()
                }
                .animation(.easeOut(duration: 0.15), value: showTimeMenu)
                .animation(.easeOut(duration: 0.15), value: showBpmMenu)
                .animation(.easeOut(duration: 0.15), value: showKeyMenu)
            }

            // Section picker overlay (centered)
            if showSectionPicker {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { showSectionPicker = false }

                VStack(spacing: 12) {
                    Text("Sección")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        ForEach(SectionMarker.sectionNames, id: \.self) { name in
                            Button {
                                markers.append(SectionMarker(name: name, position: pendingMarkerPosition))
                                showSectionPicker = false
                            } label: {
                                Text(name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(8)
                            }
                        }
                    }

                    Button {
                        showSectionPicker = false
                    } label: {
                        Text("Cancelar")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(width: 320)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
            }
        }
    }

    // sessionMenuItems removed — now using SessionMenuPopover

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
        if isArmed {
            triggerArmedSession()
            return
        }
        guard let index = currentSessionIndex, sessions.count > 1 else { return }
        let nextIndex = index < sessions.count - 1 ? index + 1 : 0
        switchSession(sessions[nextIndex])
    }

    // MARK: - Transition Handling

    private func nextSessionInList() -> MusicSession? {
        guard let index = currentSessionIndex, sessions.count > 1 else { return nil }
        let nextIndex = index < sessions.count - 1 ? index + 1 : 0
        return sessions[nextIndex]
    }

    private func handleTransition(mode: TransitionMode) {
        guard let next = nextSessionInList() else { return }
        guard !isTransitioning else { return }

        switch mode {
        case .stop:
            break // stop() already called by handleTrackEnd
        case .advance:
            switchSession(next)
            // Don't play
        case .autoAdvance:
            switchSession(next)
            audioEngine.play()
        case .crossfade:
            isTransitioning = true
            // Start fade out on current
            audioEngine.startTransitionFadeOut()
            // Load and play next on secondary engine
            configureAudioSession()
            secondaryEngine.loadSession(next)
            secondaryEngine.loadSessionMetadata(next)
            secondaryEngine.transitionDuration = audioEngine.transitionDuration
            secondaryEngine.startTransitionFadeIn()
            secondaryEngine.play()
            // After transition, finalize
            let dur = TimeInterval(audioEngine.transitionDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + dur) { [self] in
                finalizeTransition(to: next)
            }
        case .overlap:
            isTransitioning = true
            // Load and play next at full volume on secondary
            configureAudioSession()
            secondaryEngine.loadSession(next)
            secondaryEngine.loadSessionMetadata(next)
            secondaryEngine.play()
            // After transition duration, finalize
            let dur = TimeInterval(audioEngine.transitionDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + dur) { [self] in
                finalizeTransition(to: next)
            }
        case .trigger:
            // Arm the next session
            isArmed = true
        }
    }

    private func finalizeTransition(to session: MusicSession) {
        secondaryEngine.stop()
        let savedMode = audioEngine.transitionMode
        let savedDuration = audioEngine.transitionDuration
        switchSession(session)
        audioEngine.transitionMode = savedMode
        audioEngine.transitionDuration = savedDuration
        audioEngine.play()
        isTransitioning = false
    }

    private func triggerArmedSession() {
        guard isArmed, let next = nextSessionInList() else { return }
        isArmed = false
        switchSession(next)
        audioEngine.play()
    }

    // MARK: - Section Repeat

    private func activateRepeatSection() {
        guard !markers.isEmpty else { return }
        let sorted = markers.sorted { $0.position < $1.position }
        let currentPct = audioEngine.duration > 0 ? audioEngine.currentTime / audioEngine.duration : 0

        // Find which section we're currently in
        var sectionStart: Double = 0
        var sectionEnd: Double = 1
        for (i, marker) in sorted.enumerated() {
            let nextPos = i + 1 < sorted.count ? sorted[i + 1].position : 1.0
            if currentPct >= marker.position && currentPct < nextPos {
                sectionStart = marker.position
                sectionEnd = nextPos
                break
            }
        }

        audioEngine.repeatSectionStart = sectionStart * audioEngine.duration
        audioEngine.repeatSectionEnd = sectionEnd * audioEngine.duration
        audioEngine.isRepeatingSection = true
    }

    // MARK: - Session Management

    private func switchSession(_ session: MusicSession) {
        audioEngine.stop()
        currentSession = session
        tracks = session.tracks
        markers = []
        isEditMode = false
        configureAudioSession()
        audioEngine.loadSession(session)
        audioEngine.loadSessionMetadata(session)
        loadConfig(for: session)
    }

    private func loadConfig(for session: MusicSession) {
        let config: SessionConfig
        if let saved = SessionConfig.load(from: session.folderURL) {
            config = saved
        } else {
            // Create default config from session metadata
            var newConfig = SessionConfig.defaultConfig()
            newConfig.bpm = session.bpm
            newConfig.timeSignatureNumerator = session.timeSignatureNumerator
            newConfig.timeSignatureDenominator = session.timeSignatureDenominator
            newConfig.musicalKey = session.musicalKey
            newConfig.save(to: session.folderURL)
            config = newConfig
        }

        // Apply metadata
        audioEngine.bpm = config.bpm
        audioEngine.originalBpm = config.bpm
        audioEngine.musicalKey = config.musicalKey
        audioEngine.originalKey = config.musicalKey
        audioEngine.timeSignatureNumerator = config.timeSignatureNumerator
        audioEngine.timeSignatureDenominator = config.timeSignatureDenominator

        // Time controls
        audioEngine.startOffset = config.startOffset
        audioEngine.endTime = config.endTime
        audioEngine.autoFadeAt = config.autoFadeAt
        audioEngine.fadeDuration = config.fadeDuration
        audioEngine.gridOffset = config.gridOffset ?? 0
        audioEngine.masterVolume = config.masterVolume
        let loadedMode = TransitionMode(rawValue: config.transitionMode ?? "stop") ?? .stop
        audioEngine.transitionMode = loadedMode
        audioEngine.transitionDuration = config.transitionDuration ?? 5.0
        if let sid = currentSession?.id {
            sessionTransitionModes[sid] = loadedMode
        }

        // Track settings (match by filename)
        for trackConfig in config.trackSettings {
            if let idx = tracks.firstIndex(where: { $0.fileURL.lastPathComponent == trackConfig.filename }) {
                tracks[idx].volume = trackConfig.volume
                tracks[idx].pan = trackConfig.pan
                tracks[idx].isMuted = trackConfig.isMuted
                tracks[idx].isSolo = trackConfig.isSolo
                for (bandIdx, gain) in trackConfig.eqGains.enumerated() where bandIdx < tracks[idx].eqBands.count {
                    tracks[idx].eqBands[bandIdx].gain = gain
                }
                // Apply to audio engine
                audioEngine.setVolume(trackConfig.volume, for: tracks[idx].id)
                audioEngine.setPan(trackConfig.pan, for: tracks[idx].id)
                audioEngine.updateEQ(for: tracks[idx].id, bands: tracks[idx].eqBands)
            }
        }
        audioEngine.applySoloState(tracks: tracks)

        // Markers
        markers = config.markers.map { SectionMarker(name: $0.name, position: $0.position) }
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

        // Load metadata and transition modes for all sessions
        for i in sessions.indices {
            if let config = SessionConfig.load(from: sessions[i].folderURL) {
                sessions[i].bpm = config.bpm
                sessions[i].timeSignatureNumerator = config.timeSignatureNumerator
                sessions[i].timeSignatureDenominator = config.timeSignatureDenominator
                sessions[i].musicalKey = config.musicalKey
                sessionTransitionModes[sessions[i].id] = TransitionMode(rawValue: config.transitionMode ?? "stop") ?? .stop
            }
        }

        // Auto-load the first session
        if let first = sessions.first {
            switchSession(first)
        }
    }

    private func deleteSession(_ session: MusicSession) {
        if session.id == currentSession?.id {
            audioEngine.stop()
            currentSession = nil
            tracks = []
        }
        try? FileManager.default.removeItem(at: session.folderURL)
        sessions.removeAll { $0.id == session.id }
        if currentSession == nil, let first = sessions.first {
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
    let onConfirm: (String) -> Void
    let onCancel: () -> Void
    @State private var editableName: String = ""

    private let keys = AudioEngineManager.allKeys

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Editable session name
                    HStack {
                        Text("Nombre")
                            .font(.subheadline.bold())
                            .frame(width: 70, alignment: .leading)
                        TextField("Nombre de sesión", text: $editableName)
                            .font(.system(.body))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }

                    // BPM
                    HStack {
                        Text("BPM")
                            .font(.subheadline.bold())
                            .frame(width: 70, alignment: .leading)
                        TextField("120", text: $bpm)
                            .keyboardType(.numberPad)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 70)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }

                    // Time Signature
                    HStack {
                        Text("Compás")
                            .font(.subheadline.bold())
                            .frame(width: 70, alignment: .leading)
                        TextField("4", text: $numerator)
                            .keyboardType(.numberPad)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 40)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        Text("/")
                            .font(.body)
                        TextField("4", text: $denominator)
                            .keyboardType(.numberPad)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 40)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }

                    // Key grid
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tono")
                            .font(.subheadline.bold())

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                            ForEach(keys, id: \.self) { k in
                                Button(action: { key = k }) {
                                    Text(k)
                                        .font(.system(.caption, design: .rounded).bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(key == k ? Color.accentColor : Color.secondary.opacity(0.1))
                                        .foregroundColor(key == k ? .white : .primary)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Configurar Sesión")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Omitir") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Confirmar") { onConfirm(editableName.trimmingCharacters(in: .whitespaces)) }
                        .bold()
                        .disabled(editableName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { editableName = sessionName }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
