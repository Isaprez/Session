import SwiftUI

struct WaveformBar: View {
    let progress: CGFloat
    let levelHistory: [Float]
    let isPlaying: Bool
    let onSeek: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))

                // Waveform
                Canvas { context, size in
                    let count = levelHistory.count
                    guard count > 0 else { return }

                    let slotWidth = size.width / CGFloat(count)
                    let midY = size.height / 2

                    for (i, level) in levelHistory.enumerated() {
                        let x = CGFloat(i) * slotWidth + slotWidth / 2
                        let barH = max(CGFloat(level) * size.height * 0.9, 1)

                        let rect = CGRect(
                            x: x - slotWidth / 2 + 0.5,
                            y: midY - barH / 2,
                            width: max(slotWidth - 1, 1),
                            height: barH
                        )
                        let color: Color = CGFloat(i) / CGFloat(count) <= progress ? .green : .green.opacity(0.25)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Playhead line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: h)
                    .position(x: max(w * progress, 1), y: h / 2)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .gesture(
                isPlaying ? nil :
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let pct = min(max(value.location.x / w, 0), 1)
                        onSeek(pct)
                    }
            )
        }
    }
}

struct FadeIcon: View {
    let mode: AudioEngineManager.FadeMode

    var body: some View {
        Canvas { context, size in
            var path = Path()
            if mode == .out {
                // Fade out: tall on left, short on right
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
            } else {
                // Fade in: short on left, tall on right
                path.move(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
            }
            context.fill(path, with: .foreground)
        }
    }
}

struct TransportBar: View {
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onPlayPause: () -> Void
    let onStop: () -> Void
    let onPrev: () -> Void
    let onNext: () -> Void
    let isFading: Bool
    let fadeMode: AudioEngineManager.FadeMode
    let onFadeTap: () -> Void
    let onSettingsTap: () -> Void
    @Binding var startOffset: TimeInterval
    @Binding var endTime: TimeInterval
    @Binding var autoFadeAt: TimeInterval
    let maxDuration: TimeInterval
    let sessionMenuContent: AnyView
    let sessionName: String
    var masterLevel: Float = 0
    var levelHistory: [Float] = []
    let onSeek: (TimeInterval) -> Void
    @Binding var bpm: Double
    var originalBpm: Double
    @Binding var musicalKey: String
    var originalKey: String
    var timeSignatureNumerator: Int
    var timeSignatureDenominator: Int

    @State private var blinkVisible = true
    @State private var showTimeMenu = false
    @State private var showBpmMenu = false
    @State private var showKeyMenu = false

    var body: some View {
        VStack(spacing: 8) {
            // Controls
            HStack(spacing: 16) {
                // Session menu - far left
                Menu { sessionMenuContent } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title3)
                        .foregroundColor(.primary)
                }

                Spacer()

                // Center transport controls
                HStack(spacing: 16) {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }

                    Button(action: onPrev) {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }

                    Button(action: onPlayPause) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.accentColor)
                    }

                    Button(action: onNext) {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                }

                // Info buttons group
                HStack(spacing: 8) {
                    FadeIcon(mode: fadeMode)
                        .frame(width: 24, height: 18)
                        .foregroundColor(isFading ? Color.orange : .primary)
                        .opacity(isFading ? (blinkVisible ? 1.0 : 0.2) : 1.0)
                        .contentShape(Rectangle())
                        .onTapGesture { onFadeTap() }

                    Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(8)
                        .foregroundColor(.primary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showBpmMenu = false
                            showKeyMenu = false
                            showTimeMenu.toggle()
                        }

                    HStack(spacing: 2) {
                        Text("\(Int(bpm))")
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(bpm != originalBpm ? .orange : .primary)
                        Text("bpm")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showTimeMenu = false
                        showKeyMenu = false
                        showBpmMenu.toggle()
                    }

                    Text(musicalKey)
                        .font(.system(.caption, design: .rounded).bold())
                        .foregroundColor(musicalKey != originalKey ? .orange : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showTimeMenu = false
                            showBpmMenu = false
                            showKeyMenu.toggle()
                        }
                }

                Spacer()

                // Settings - far right
                Button(action: onSettingsTap) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)

            // Waveform progress bar
            WaveformBar(
                progress: duration > 0 ? CGFloat(currentTime / duration) : 0,
                levelHistory: levelHistory,
                isPlaying: isPlaying,
                onSeek: { pct in
                    let seekTime = Double(pct) * maxDuration
                    startOffset = seekTime
                    onSeek(seekTime)
                }
            )
            .frame(height: 28)
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .top) {
            ZStack {
                if showTimeMenu {
                    TimePopover(
                        startOffset: $startOffset,
                        endTime: $endTime,
                        autoFadeAt: $autoFadeAt,
                        duration: maxDuration,
                        onDismiss: { showTimeMenu = false }
                    )
                    .offset(y: -210)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                }
                if showBpmMenu {
                    BpmPopover(
                        bpm: $bpm,
                        originalBpm: originalBpm,
                        timeSignatureNumerator: timeSignatureNumerator,
                        timeSignatureDenominator: timeSignatureDenominator,
                        onDismiss: { showBpmMenu = false }
                    )
                    .offset(y: -210)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                }
                if showKeyMenu {
                    KeyPopover(
                        musicalKey: $musicalKey,
                        originalKey: originalKey,
                        onDismiss: { showKeyMenu = false }
                    )
                    .offset(y: -180)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.15), value: showTimeMenu)
            .animation(.easeOut(duration: 0.15), value: showBpmMenu)
            .animation(.easeOut(duration: 0.15), value: showKeyMenu)
            .allowsHitTesting(showTimeMenu || showBpmMenu || showKeyMenu)
        }
        .onChange(of: isFading) { fading in
            if fading {
                startBlinking()
            } else {
                blinkVisible = true
            }
        }
    }

    private func startBlinking() {
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            blinkVisible.toggle()
        }
    }

    private func progressWidth(totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return totalWidth * CGFloat(currentTime / duration)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Compact Time Input

struct CompactTimeRow: View {
    let label: String
    @Binding var value: TimeInterval
    let maxValue: TimeInterval

    @State private var minutesText = ""
    @State private var secondsText = ""

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)

            Button(action: { adjust(by: -1) }) {
                Image(systemName: "minus.circle.fill")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            HStack(spacing: 1) {
                TextField("00", text: $minutesText)
                    .keyboardType(.numberPad)
                    .frame(width: 22)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: minutesText) { _ in applyText() }
                Text(":")
                    .foregroundColor(.secondary)
                TextField("00", text: $secondsText)
                    .keyboardType(.numberPad)
                    .frame(width: 22)
                    .multilineTextAlignment(.leading)
                    .onChange(of: secondsText) { _ in applyText() }
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)

            Button(action: { adjust(by: 1) }) {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .onAppear { syncFromValue() }
        .onChange(of: value) { _ in syncFromValue() }
    }

    private func syncFromValue() {
        let mins = Int(value) / 60
        let secs = Int(value) % 60
        let newMin = String(format: "%02d", mins)
        let newSec = String(format: "%02d", secs)
        if minutesText != newMin { minutesText = newMin }
        if secondsText != newSec { secondsText = newSec }
    }

    private func applyText() {
        let mins = Int(minutesText) ?? 0
        let secs = Int(secondsText) ?? 0
        value = min(max(TimeInterval(mins * 60 + secs), 0), maxValue)
    }

    private func adjust(by seconds: Int) {
        value = min(max(value + TimeInterval(seconds), 0), maxValue)
    }
}

// MARK: - Time Popover

struct TimePopover: View {
    @Binding var startOffset: TimeInterval
    @Binding var endTime: TimeInterval
    @Binding var autoFadeAt: TimeInterval
    let duration: TimeInterval
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tiempo")
                    .font(.caption.bold())
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            CompactTimeRow(label: "Inicio", value: $startOffset, maxValue: duration)
            CompactTimeRow(label: "Fin", value: $endTime, maxValue: duration)
            CompactTimeRow(label: "Fade out", value: $autoFadeAt, maxValue: duration)

            Text("0:00 en Fin = hasta el final. 0:00 en Fade = desactivado.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}

// MARK: - BPM Popover

struct BpmPopover: View {
    @Binding var bpm: Double
    let originalBpm: Double
    let timeSignatureNumerator: Int
    let timeSignatureDenominator: Int
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tempo")
                    .font(.caption.bold())
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // BPM control
            HStack(spacing: 8) {
                Text("BPM")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)

                Button(action: { bpm = max(bpm - 1, 20) }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text("\(Int(bpm))")
                    .font(.system(.body, design: .monospaced).bold())
                    .frame(width: 50)
                    .multilineTextAlignment(.center)

                Button(action: { bpm = min(bpm + 1, 300) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                if bpm != originalBpm {
                    Button(action: { bpm = originalBpm }) {
                        Text("Reset")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Time signature (read-only info)
            HStack {
                Text("Signatura")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(timeSignatureNumerator)/\(timeSignatureDenominator)")
                    .font(.system(.body, design: .monospaced).bold())
            }

            Text("Original: \(Int(originalBpm)) BPM")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(width: 240)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}

// MARK: - Key Popover

struct KeyPopover: View {
    @Binding var musicalKey: String
    let originalKey: String
    let onDismiss: () -> Void

    private let keys = AudioEngineManager.allKeys

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tono")
                    .font(.caption.bold())
                Spacer()
                if musicalKey != originalKey {
                    Button(action: { musicalKey = originalKey }) {
                        Text("Reset")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Key grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Button(action: { musicalKey = key }) {
                        Text(key)
                            .font(.system(.caption, design: .rounded).bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                musicalKey == key ? Color.accentColor :
                                key == originalKey ? Color.secondary.opacity(0.2) :
                                Color.secondary.opacity(0.1)
                            )
                            .foregroundColor(musicalKey == key ? .white : .primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Original: \(originalKey)")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(width: 240)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}
