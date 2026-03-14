import AVFoundation
import Accelerate
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

    private var currentSessionTracks: [Track] = []

    @Published var trackLevels: [UUID: Float] = [:]
    @Published var masterLevel: Float = 0
    @Published var levelHistory: [Float] = []       // zoom 0
    @Published var levelHistoryZoom1: [Float] = []  // zoom 1
    @Published var levelHistoryZoom2: [Float] = []  // zoom 2
    private let slotsZoom0 = 400
    private let slotsZoom1 = 1200
    private let slotsZoom2 = 3600
    @Published var startOffset: TimeInterval = 0 { // config: start time from time menu
        didSet { if !isPlaying { playFrom = startOffset } }
    }
    private var playFrom: TimeInterval = 0       // actual seek position for playback
    @Published var endTime: TimeInterval = 0 // 0 = use full duration
    @Published var autoFadeAt: TimeInterval = 0 // 0 = disabled
    @Published var gridOffset: TimeInterval = 0 // offset to align grid with actual beats
    @Published var isDetectingGrid = false
    @Published var gridDetected = false
    private var autoFadeTriggered = false

    // Section repeat
    @Published var isRepeatingSection = false
    @Published var isGeneratingWaveform = false
    var repeatSectionStart: TimeInterval = 0
    var repeatSectionEnd: TimeInterval = 0

    // Transition
    @Published var transitionMode: TransitionMode = .stop
    var transitionDuration: Float = 5.0
    var onTrackEnd: ((TransitionMode) -> Void)?
    private var transitionTriggered = false

    private var displayLink: CADisplayLink?
    private var startSampleTime: AVAudioFramePosition = 0
    private var startHostTime: UInt64 = 0
    private var commonFormat: AVAudioFormat?

    func loadSession(_ session: MusicSession) {
        stop()
        tearDown()
        currentSessionTracks = session.tracks

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

        // Pre-compute waveform in background
        generateWaveform(session: session)

        // Auto-detect grid offset if not already set
        if gridOffset == 0 {
            detectGridOffset(tracks: session.tracks)
        }
    }

    private func rmsLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let length = Int(buffer.frameLength)
        guard length > 0 else { return 0 }

        var maxRMS: Float = 0
        for ch in 0..<channelCount {
            let ptr = channelData[ch]
            var sumSq: Float = 0
            vDSP_dotpr(ptr, 1, ptr, 1, &sumSq, vDSP_Length(length))
            let rms = sqrtf(sumSq / Float(length))
            maxRMS = max(maxRMS, rms)
        }
        return maxRMS
    }

    private func generateWaveform(session: MusicSession) {
        let tracks = session.tracks
        let s0 = slotsZoom0
        let s1 = slotsZoom1
        let s2 = slotsZoom2

        DispatchQueue.main.async { self.isGeneratingWaveform = true }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Generate 3 resolutions progressively
            let waveform0 = self.computeWaveform(tracks: tracks, slots: s0)
            DispatchQueue.main.async {
                self.levelHistory = waveform0
                self.isGeneratingWaveform = false
            }

            let waveform1 = self.computeWaveform(tracks: tracks, slots: s1)
            DispatchQueue.main.async {
                self.levelHistoryZoom1 = waveform1
            }

            let waveform2 = self.computeWaveform(tracks: tracks, slots: s2)
            DispatchQueue.main.async {
                self.levelHistoryZoom2 = waveform2
            }
        }
    }

    private func computeWaveform(tracks: [Track], slots: Int) -> [Float] {
        var waveform = Array(repeating: Float(0), count: slots)

        for track in tracks {
            if track.isSpecial { continue }
            guard let file = try? AVAudioFile(forReading: track.fileURL) else { continue }
            let totalFrames = Int(file.length)
            guard totalFrames > 0 else { continue }
            let framesPerSlot = totalFrames / slots

            let chunkSlots = 64
            let chunkFrames = AVAudioFrameCount(framesPerSlot * chunkSlots)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames) else { continue }

            file.framePosition = 0
            var slot = 0

            while slot < slots {
                buffer.frameLength = 0
                let remaining = AVAudioFrameCount(totalFrames - Int(file.framePosition))
                guard remaining > 0 else { break }
                do {
                    try file.read(into: buffer, frameCount: min(chunkFrames, remaining))
                } catch { break }
                guard buffer.frameLength > 0, let channelData = buffer.floatChannelData else { break }

                let channelCount = Int(buffer.format.channelCount)
                let frameLen = Int(buffer.frameLength)
                let slotsInChunk = min(frameLen / max(framesPerSlot, 1), slots - slot)

                for s in 0..<slotsInChunk {
                    let start = s * framesPerSlot
                    let end = min(start + framesPerSlot, frameLen)
                    let count = end - start
                    guard count > 0 else { continue }

                    var maxRMS: Float = 0
                    for ch in 0..<channelCount {
                        let ptr = channelData[ch].advanced(by: start)
                        var sumSq: Float = 0
                        vDSP_dotpr(ptr, 1, ptr, 1, &sumSq, vDSP_Length(count))
                        let rms = sqrtf(sumSq / Float(count))
                        maxRMS = max(maxRMS, rms)
                    }
                    let db = 20 * log10f(max(maxRMS, 1e-6))
                    let normalized = min(max((db + 40) / 40, 0), 1.0)
                    waveform[slot + s] = max(waveform[slot + s], normalized)
                }
                slot += slotsInChunk
            }
        }

        return waveform
    }

    // MARK: - Auto Grid Detection

    func autoDetectGridOffset() {
        isDetectingGrid = true
        gridDetected = false
        gridOffset = 0
        print("[GridDetect] Starting auto-detection, tracks: \(currentSessionTracks.count), audioFiles: \(audioFiles.count)")
        detectGridOffset(tracks: currentSessionTracks)
    }

    private func detectGridOffset(tracks: [Track]) {
        let detectionBpm = originalBpm > 0 ? originalBpm : bpm
        guard detectionBpm > 0 else {
            print("[GridDetect] Aborted: bpm = 0")
            DispatchQueue.main.async { self.isDetectingGrid = false }
            return
        }

        DispatchQueue.main.async { self.isDetectingGrid = true }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Prefer click track for detection (has clear accents), fallback to first music track
            let clickTrack = tracks.first(where: { $0.isClick })
            let analysisTrack = clickTrack ?? tracks.first(where: { !$0.isSpecial })

            guard let track = analysisTrack else {
                print("[GridDetect] No suitable track found")
                DispatchQueue.main.async { self.isDetectingGrid = false }
                return
            }

            let isClick = track.isClick
            print("[GridDetect] Analyzing: \(track.name) (isClick: \(isClick))")
            print("[GridDetect] BPM for detection: \(detectionBpm)")

            // Open file for analysis — try URL first, then copy from existing
            var file: AVAudioFile?
            if let f = try? AVAudioFile(forReading: track.fileURL) {
                file = f
                print("[GridDetect] Opened file from URL")
            } else if let existing = self.audioFiles[track.id] {
                // Security scope may have expired — copy format and read from existing
                let url = existing.url
                if let f = try? AVAudioFile(forReading: url) {
                    file = f
                    print("[GridDetect] Opened file from audioFiles URL")
                }
            }

            guard let file = file else {
                print("[GridDetect] Failed to open any file")
                DispatchQueue.main.async { self.isDetectingGrid = false }
                return
            }

            let sampleRate = file.processingFormat.sampleRate
            let totalFrames = Int(file.length)
            guard totalFrames > 0 else {
                print("[GridDetect] Empty file")
                DispatchQueue.main.async { self.isDetectingGrid = false }
                return
            }

            // Analysis window: 5ms for precise transient detection
            let windowFrames = Int(sampleRate * 0.005)
            let bufferCapacity = AVAudioFrameCount(windowFrames * 200)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: bufferCapacity) else {
                print("[GridDetect] Failed to create buffer")
                DispatchQueue.main.async { self.isDetectingGrid = false }
                return
            }

            // Scan first 10 seconds
            let maxScanFrames = min(totalFrames, Int(sampleRate * 10))

            struct WindowPeak {
                let time: Double
                let amplitude: Float
            }
            var peaks: [WindowPeak] = []

            file.framePosition = 0
            var scannedFrames = 0
            while scannedFrames < maxScanFrames {
                buffer.frameLength = 0
                let remaining = AVAudioFrameCount(maxScanFrames - scannedFrames)
                guard remaining > 0 else { break }
                do {
                    try file.read(into: buffer, frameCount: min(bufferCapacity, remaining))
                } catch { break }
                guard buffer.frameLength > 0, let channelData = buffer.floatChannelData else { break }

                let frameLen = Int(buffer.frameLength)
                let channelCount = Int(buffer.format.channelCount)
                var pos = 0
                while pos + windowFrames <= frameLen {
                    var maxAmp: Float = 0
                    for ch in 0..<channelCount {
                        let ptr = channelData[ch].advanced(by: pos)
                        var peak: Float = 0
                        vDSP_maxv(ptr, 1, &peak, vDSP_Length(windowFrames))
                        var negPeak: Float = 0
                        vDSP_minv(ptr, 1, &negPeak, vDSP_Length(windowFrames))
                        maxAmp = max(maxAmp, max(peak, -negPeak))
                    }
                    let time = Double(scannedFrames + pos) / sampleRate
                    peaks.append(WindowPeak(time: time, amplitude: maxAmp))
                    pos += windowFrames
                }
                scannedFrames += frameLen
            }

            print("[GridDetect] Collected \(peaks.count) windows")

            guard !peaks.isEmpty else {
                DispatchQueue.main.async { self.isDetectingGrid = false }
                return
            }
            let globalPeak = peaks.map(\.amplitude).max() ?? 0
            print("[GridDetect] Global peak amplitude: \(globalPeak)")
            guard globalPeak > 0 else {
                DispatchQueue.main.async { self.isDetectingGrid = false }
                return
            }

            // Find transients: windows where amplitude jumps above threshold
            let onsetThreshold = globalPeak * 0.2
            var transients: [WindowPeak] = []
            let minGap = 0.03 // min 30ms between transients

            for p in peaks {
                guard p.amplitude >= onsetThreshold else { continue }
                if let last = transients.last, p.time - last.time < minGap { continue }
                transients.append(p)
            }

            print("[GridDetect] Found \(transients.count) transients")
            for (i, t) in transients.prefix(10).enumerated() {
                print("[GridDetect]   #\(i): time=\(String(format: "%.3f", t.time))s amp=\(String(format: "%.4f", t.amplitude))")
            }

            guard !transients.isEmpty else {
                DispatchQueue.main.async { self.isDetectingGrid = false }
                return
            }

            var detectedOffset: Double = transients[0].time

            if isClick && transients.count >= 3 {
                // Click track: measure actual BPM from click intervals
                var intervals: [Double] = []
                for i in 1..<min(transients.count, 20) {
                    let interval = transients[i].time - transients[i - 1].time
                    // Only consider reasonable intervals (30-300 BPM range)
                    if interval > 0.2 && interval < 2.0 {
                        intervals.append(interval)
                    }
                }

                print("[GridDetect] Click intervals: \(intervals.prefix(10).map { String(format: "%.3f", $0) })")

                if !intervals.isEmpty {
                    // Median interval = beat duration
                    let sortedIntervals = intervals.sorted()
                    let medianInterval = sortedIntervals[sortedIntervals.count / 2]
                    var measuredBpm = 60.0 / medianInterval

                    // Fix double/half BPM: if measured is ~2x or ~0.5x the configured, adjust
                    if detectionBpm > 0 {
                        let ratio = measuredBpm / detectionBpm
                        if ratio > 1.8 && ratio < 2.2 {
                            // Detected double — clicks have subdivisions or double hits
                            measuredBpm /= 2.0
                            print("[GridDetect] Corrected double BPM: \(String(format: "%.1f", measuredBpm * 2)) -> \(String(format: "%.1f", measuredBpm))")
                        } else if ratio > 0.45 && ratio < 0.55 {
                            // Detected half — accent-only pattern
                            measuredBpm *= 2.0
                            print("[GridDetect] Corrected half BPM: \(String(format: "%.1f", measuredBpm / 2)) -> \(String(format: "%.1f", measuredBpm))")
                        }
                    }

                    print("[GridDetect] Measured BPM from clicks: \(String(format: "%.1f", measuredBpm)) (configured: \(detectionBpm))")

                    // Only correct if measured differs meaningfully but is in a reasonable range
                    if abs(measuredBpm - detectionBpm) > 0.5 && abs(measuredBpm - detectionBpm) < 20 {
                        print("[GridDetect] BPM correction: \(String(format: "%.1f", detectionBpm)) -> \(String(format: "%.1f", measuredBpm))")
                        DispatchQueue.main.async {
                            self.originalBpm = measuredBpm
                            self.bpm = measuredBpm
                        }
                    }
                }

                // Find accent (loudest click = beat 1)
                // Look at amplitude of each transient — accent is noticeably louder
                let avgAmp = transients.prefix(12).map(\.amplitude).reduce(0, +) / Float(min(transients.count, 12))
                let accentThreshold = avgAmp * 1.15 // accent is at least 15% louder than average

                // Find first accent
                let accents = transients.prefix(20).filter { $0.amplitude > accentThreshold }
                print("[GridDetect] Avg click amp: \(String(format: "%.4f", avgAmp)), accent threshold: \(String(format: "%.4f", accentThreshold))")
                print("[GridDetect] Accents found: \(accents.count)")
                for (i, a) in accents.prefix(5).enumerated() {
                    print("[GridDetect]   Accent #\(i): time=\(String(format: "%.3f", a.time))s amp=\(String(format: "%.4f", a.amplitude))")
                }

                if let firstAccent = accents.first {
                    detectedOffset = firstAccent.time
                } else {
                    // No clear accent — use first transient
                    detectedOffset = transients[0].time
                }
            }

            let offset = min(detectedOffset, 5.0)
            print("[GridDetect] Final offset: \(String(format: "%.3f", offset))s")

            DispatchQueue.main.async {
                self.gridOffset = offset
                self.isDetectingGrid = false
                self.gridDetected = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.gridDetected = false
                }
            }
        }
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

        let seekTime = playFrom

        for (trackID, player) in playerNodes {
            guard let file = audioFiles[trackID] else { continue }
            let sampleRate = file.processingFormat.sampleRate
            let offsetFrames = AVAudioFramePosition(seekTime * sampleRate)
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

        currentTime = seekTime
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
        playFrom = startOffset
        currentTime = startOffset
        autoFadeTriggered = false
        transitionTriggered = false
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
        // If paused, need full re-seek on next play
        if isPaused {
            isPaused = false
            for player in playerNodes.values {
                player.stop()
            }
        }
        playFrom = time
        currentTime = time
    }

    func seekWhilePlaying(to time: TimeInterval) {
        guard isPlaying else { return }
        // Stop all players and reschedule from the new time
        for player in playerNodes.values {
            player.stop()
        }
        for (trackID, player) in playerNodes {
            guard let file = audioFiles[trackID] else { continue }
            let sampleRate = file.processingFormat.sampleRate
            let offsetFrames = AVAudioFramePosition(time * sampleRate)
            let totalFrames = file.length
            let startFrame = min(offsetFrames, totalFrames)
            let frameCount = AVAudioFrameCount(totalFrames - startFrame)
            if frameCount > 0 {
                player.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil)
            }
            player.play()
        }
        playFrom = time
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
        var currentStep = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            currentStep += 1
            // Exponential curve: stays loud longer, then drops faster at the end
            let progress = Float(currentStep) / Float(steps)
            let curve = 1.0 - powf(progress, 3.0)
            let newVol = self.volumeBeforeFade * curve
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
        let time = Double(playerTime.sampleTime) / sampleRate + playFrom

        DispatchQueue.main.async {
            if time >= 0 {
                self.currentTime = time
            }

            // Section repeat: when time passes section end, jump back and disable
            if self.isRepeatingSection && self.repeatSectionEnd > 0 && time >= self.repeatSectionEnd {
                self.isRepeatingSection = false
                self.seekWhilePlaying(to: self.repeatSectionStart)
                return
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

            // Pre-trigger for crossfade/overlap: start transition early
            if (self.transitionMode == .crossfade || self.transitionMode == .overlap)
                && !self.transitionTriggered
                && self.transitionDuration > 0
                && time >= stopAt - TimeInterval(self.transitionDuration) {
                self.transitionTriggered = true
                self.onTrackEnd?(self.transitionMode)
            }

            if time >= stopAt {
                self.handleTrackEnd()
            }
        }
    }

    // MARK: - Track End Handling

    private func handleTrackEnd() {
        switch transitionMode {
        case .stop:
            stop()
        case .advance:
            stop()
            onTrackEnd?(.advance)
        case .autoAdvance:
            stop()
            onTrackEnd?(.autoAdvance)
        case .crossfade, .overlap:
            // Pre-trigger already fired; just stop current
            stop()
        case .trigger:
            stop()
        }
    }

    func startTransitionFadeOut() {
        guard transitionDuration > 0 else { return }
        let steps = Int(transitionDuration * 30)
        let interval = TimeInterval(transitionDuration) / TimeInterval(steps)
        let startVol = engine.mainMixerNode.outputVolume
        var currentStep = 0

        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            currentStep += 1
            let progress = Float(currentStep) / Float(steps)
            let curve = 1.0 - powf(progress, 3.0)
            self.engine.mainMixerNode.outputVolume = startVol * curve
            if currentStep >= steps {
                timer.invalidate()
            }
        }
    }

    func startTransitionFadeIn() {
        guard transitionDuration > 0 else { return }
        engine.mainMixerNode.outputVolume = 0
        let steps = Int(transitionDuration * 30)
        let interval = TimeInterval(transitionDuration) / TimeInterval(steps)
        let targetVol = masterVolume
        var currentStep = 0

        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            currentStep += 1
            let progress = Float(currentStep) / Float(steps)
            self.engine.mainMixerNode.outputVolume = targetVol * progress
            if currentStep >= steps {
                timer.invalidate()
                self.engine.mainMixerNode.outputVolume = targetVol
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

