import AVFoundation
import Combine

class AudioEngineManager: ObservableObject {
    private let engine = AVAudioEngine()
    private var playerNodes: [UUID: AVAudioPlayerNode] = [:]
    private var eqNodes: [UUID: AVAudioUnitEQ] = [:]
    private var timePitchNodes: [UUID: AVAudioUnitTimePitch] = [:]
    private var audioFiles: [UUID: AVAudioFile] = [:]

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var masterVolume: Float = 1.0 {
        didSet {
            if !isFading { engine.mainMixerNode.outputVolume = masterVolume }
        }
    }
    @Published var isFading = false
    @Published var fadeMode: FadeMode = .out
    var fadeDuration: Float = 10.0
    private var fadeTimer: Timer?
    private var volumeBeforeFade: Float = 1.0

    // Tempo & Key
    @Published var bpm: Double = 120 {
        didSet { applyTempoRate() }
    }
    var originalBpm: Double = 120
    @Published var musicalKey: String = "C" {
        didSet { applyPitchShift() }
    }
    var originalKey: String = "C"
    @Published var timeSignatureNumerator: Int = 4
    @Published var timeSignatureDenominator: Int = 4

    enum FadeMode {
        case out, `in`
    }

    @Published var trackLevels: [UUID: Float] = [:]
    @Published var masterLevel: Float = 0
    @Published var levelHistory: [Float] = []
    private let levelHistorySlots = 200
    @Published var startOffset: TimeInterval = 0
    @Published var endTime: TimeInterval = 0 // 0 = use full duration
    @Published var autoFadeAt: TimeInterval = 0 // 0 = disabled
    private var autoFadeTriggered = false

    private var displayLink: CADisplayLink?
    private var startSampleTime: AVAudioFramePosition = 0
    private var startHostTime: UInt64 = 0
    private var commonFormat: AVAudioFormat?

    func loadSession(_ session: MusicSession) {
        stop()
        tearDown()

        // Determine common format from first track
        guard let firstFile = try? AVAudioFile(forReading: session.tracks[0].fileURL) else { return }
        commonFormat = firstFile.processingFormat

        for track in session.tracks {
            guard let file = try? AVAudioFile(forReading: track.fileURL) else { continue }

            let player = AVAudioPlayerNode()
            let eq = AVAudioUnitEQ(numberOfBands: 5)
            let timePitch = AVAudioUnitTimePitch()

            // Configure EQ bands
            for (i, band) in track.eqBands.enumerated() {
                eq.bands[i].filterType = .parametric
                eq.bands[i].frequency = band.frequency
                eq.bands[i].gain = band.gain
                eq.bands[i].bandwidth = band.bandwidth
                eq.bands[i].bypass = false
            }

            engine.attach(player)
            engine.attach(eq)
            engine.attach(timePitch)

            // Connect: player -> eq -> timePitch -> mainMixer
            engine.connect(player, to: eq, format: file.processingFormat)
            engine.connect(eq, to: timePitch, format: file.processingFormat)
            engine.connect(timePitch, to: engine.mainMixerNode, format: file.processingFormat)

            player.volume = track.volume
            player.pan = track.pan

            // Install tap for level metering
            let trackID = track.id
            eq.installTap(onBus: 0, bufferSize: 1024, format: file.processingFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                let level = self.rmsLevel(buffer: buffer)
                DispatchQueue.main.async {
                    self.trackLevels[trackID] = level
                }
            }

            playerNodes[track.id] = player
            eqNodes[track.id] = eq
            timePitchNodes[track.id] = timePitch
            audioFiles[track.id] = file

            // Calculate max duration
            let fileDuration = Double(file.length) / file.processingFormat.sampleRate
            if fileDuration > duration {
                duration = fileDuration
            }
        }

        do {
            try engine.start()

            // Master level metering
            let mainMixer = engine.mainMixerNode
            let masterFormat = mainMixer.outputFormat(forBus: 0)
            mainMixer.installTap(onBus: 0, bufferSize: 1024, format: masterFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                let level = self.rmsLevel(buffer: buffer)
                DispatchQueue.main.async {
                    self.masterLevel = level
                }
            }
        } catch {
            print("Error starting audio engine: \(error)")
        }

        // Pre-compute waveform from all tracks
        generateWaveform(session: session)
    }

    private func generateWaveform(session: MusicSession) {
        let slots = levelHistorySlots
        var waveform = Array(repeating: Float(0), count: slots)

        for track in session.tracks {
            guard let file = try? AVAudioFile(forReading: track.fileURL) else { continue }
            let totalFrames = file.length
            let framesPerSlot = max(totalFrames / Int64(slots), 1)
            let bufferSize = AVAudioFrameCount(framesPerSlot)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: bufferSize) else { continue }

            file.framePosition = 0
            for slot in 0..<slots {
                buffer.frameLength = 0
                do {
                    try file.read(into: buffer, frameCount: min(bufferSize, AVAudioFrameCount(totalFrames - file.framePosition)))
                } catch { break }

                guard buffer.frameLength > 0 else { break }

                let level = rmsLevel(buffer: buffer)
                waveform[slot] = max(waveform[slot], level)
            }
        }

        levelHistory = waveform
    }

    private func rmsLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var totalRMS: Float = 0
        for ch in 0..<channelCount {
            let data = channelData[ch]
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += data[i] * data[i]
            }
            totalRMS += sqrtf(sum / Float(frameLength))
        }
        let avgRMS = totalRMS / Float(channelCount)
        // Convert to 0...1 range (clamp)
        return min(avgRMS * 1.8, 1.0)
    }

    func play() {
        guard !isPlaying else { return }
        guard !playerNodes.isEmpty else { return }

        // Restart engine if needed
        if !engine.isRunning {
            do { try engine.start() } catch {
                print("Error restarting engine: \(error)")
                return
            }
        }

        for (trackID, player) in playerNodes {
            guard let file = audioFiles[trackID] else { continue }
            let sampleRate = file.processingFormat.sampleRate
            let offsetFrames = AVAudioFramePosition(startOffset * sampleRate)
            let totalFrames = file.length
            let startFrame = min(offsetFrames, totalFrames)
            let frameCount = AVAudioFrameCount(totalFrames - startFrame)

            if frameCount > 0 {
                player.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil)
            }
        }

        // Start all players simultaneously
        for player in playerNodes.values {
            player.play()
        }

        currentTime = startOffset
        autoFadeTriggered = false
        isPlaying = true
        startTimeTracking()
    }

    func pause() {
        guard isPlaying else { return }
        for player in playerNodes.values {
            player.pause()
        }
        isPlaying = false
        isPaused = true
        stopTimeTracking()
    }

    func resume() {
        guard !isPlaying, isPaused else { return }
        for player in playerNodes.values {
            player.play()
        }
        isPlaying = true
        isPaused = false
        startTimeTracking()
    }

    private var isPaused = false

    func stop() {
        for player in playerNodes.values {
            player.stop()
        }
        isPlaying = false
        isPaused = false
        currentTime = 0
        autoFadeTriggered = false
        stopTimeTracking()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if isPaused {
            resume()
        } else {
            play()
        }
    }

    func seekTo(_ time: TimeInterval) {
        guard !isPlaying else { return }
        startOffset = time
        currentTime = time
    }

    func loadSessionMetadata(_ session: MusicSession) {
        originalBpm = session.bpm
        bpm = session.bpm
        originalKey = session.musicalKey
        musicalKey = session.musicalKey
        timeSignatureNumerator = session.timeSignatureNumerator
        timeSignatureDenominator = session.timeSignatureDenominator
    }

    // MARK: - Tempo & Key

    static let allKeys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private func applyTempoRate() {
        guard originalBpm > 0 else { return }
        let rate = Float(bpm / originalBpm)
        for tp in timePitchNodes.values {
            tp.rate = rate
        }
    }

    private func applyPitchShift() {
        let keys = AudioEngineManager.allKeys
        guard let originalIndex = keys.firstIndex(of: originalKey),
              let newIndex = keys.firstIndex(of: musicalKey) else { return }
        var semitones = newIndex - originalIndex
        if semitones > 6 { semitones -= 12 }
        if semitones < -6 { semitones += 12 }
        let cents = Float(semitones * 100)
        for tp in timePitchNodes.values {
            tp.pitch = cents
        }
    }

    // MARK: - Track Controls

    func setVolume(_ volume: Float, for trackID: UUID) {
        playerNodes[trackID]?.volume = volume
    }

    func setPan(_ pan: Float, for trackID: UUID) {
        playerNodes[trackID]?.pan = pan
    }

    func setMute(_ muted: Bool, for trackID: UUID) {
        if muted {
            playerNodes[trackID]?.volume = 0
        }
    }

    func applySoloState(tracks: [Track]) {
        let hasSolo = tracks.contains { $0.isSolo }
        for track in tracks {
            if hasSolo {
                let shouldPlay = track.isSolo && !track.isMuted
                playerNodes[track.id]?.volume = shouldPlay ? track.volume : 0
            } else {
                playerNodes[track.id]?.volume = track.isMuted ? 0 : track.volume
            }
        }
    }

    func updateEQ(for trackID: UUID, bands: [EQBand]) {
        guard let eq = eqNodes[trackID] else { return }
        for (i, band) in bands.enumerated() where i < 5 {
            eq.bands[i].frequency = band.frequency
            eq.bands[i].gain = band.gain
            eq.bands[i].bandwidth = band.bandwidth
        }
    }

    // MARK: - Fade

    func toggleFade() {
        if isFading {
            cancelFade()
            return
        }

        if fadeMode == .out {
            startFadeOut()
        } else {
            startFadeIn()
        }
    }

    private func startFadeOut() {
        volumeBeforeFade = masterVolume
        isFading = true
        let steps = 60
        let interval = TimeInterval(fadeDuration) / TimeInterval(steps)
        let decrement = volumeBeforeFade / Float(steps)
        var currentStep = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            currentStep += 1
            let newVol = self.volumeBeforeFade - decrement * Float(currentStep)
            DispatchQueue.main.async {
                self.engine.mainMixerNode.outputVolume = max(newVol, 0)
                self.masterVolume = max(newVol, 0)
            }
            if currentStep >= steps {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.engine.mainMixerNode.outputVolume = 0
                    self.masterVolume = 0
                    self.isFading = false
                    self.fadeMode = .in
                }
            }
        }
    }

    private func startFadeIn() {
        let targetVolume = volumeBeforeFade > 0 ? volumeBeforeFade : Float(1.0)
        isFading = true
        let steps = 60
        let interval = TimeInterval(fadeDuration) / TimeInterval(steps)
        let increment = targetVolume / Float(steps)
        var currentStep = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            currentStep += 1
            let newVol = increment * Float(currentStep)
            DispatchQueue.main.async {
                self.engine.mainMixerNode.outputVolume = min(newVol, targetVolume)
                self.masterVolume = min(newVol, targetVolume)
            }
            if currentStep >= steps {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.engine.mainMixerNode.outputVolume = targetVolume
                    self.masterVolume = targetVolume
                    self.isFading = false
                    self.fadeMode = .out
                }
            }
        }
    }

    private func cancelFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        isFading = false
    }

    // MARK: - Time Tracking

    private func startTimeTracking() {
        let link = CADisplayLink(target: self, selector: #selector(updateTime))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopTimeTracking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateTime() {
        guard isPlaying,
              let firstPlayer = playerNodes.values.first,
              let nodeTime = firstPlayer.lastRenderTime,
              let playerTime = firstPlayer.playerTime(forNodeTime: nodeTime) else { return }

        let sampleRate = playerTime.sampleRate
        let time = Double(playerTime.sampleTime) / sampleRate + startOffset

        DispatchQueue.main.async {
            if time >= 0 {
                self.currentTime = time
            }

            // Auto fade at specific time
            if self.autoFadeAt > 0 && !self.autoFadeTriggered && time >= self.autoFadeAt {
                self.autoFadeTriggered = true
                if !self.isFading {
                    self.fadeMode = .out
                    self.toggleFade()
                }
            }

            // Stop at endTime or duration
            let stopAt = self.endTime > 0 ? self.endTime : self.duration
            if time >= stopAt {
                self.stop()
            }
        }
    }

    // MARK: - Teardown

    private func tearDown() {
        // Remove taps before detaching
        for eq in eqNodes.values {
            eq.removeTap(onBus: 0)
        }
        if engine.isRunning {
            engine.mainMixerNode.removeTap(onBus: 0)
        }
        engine.stop()
        for player in playerNodes.values {
            engine.detach(player)
        }
        for eq in eqNodes.values {
            engine.detach(eq)
        }
        for tp in timePitchNodes.values {
            engine.detach(tp)
        }
        playerNodes.removeAll()
        eqNodes.removeAll()
        timePitchNodes.removeAll()
        audioFiles.removeAll()
        trackLevels.removeAll()
        masterLevel = 0
        duration = 0
        currentTime = 0
    }

    deinit {
        tearDown()
    }
}

