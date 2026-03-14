import SwiftUI

struct WaveformBar: View {
    let progress: CGFloat
    let levelHistory: [Float]
    let isPlaying: Bool
    let onSeek: (CGFloat) -> Void
    var bpm: Double = 0
    var timeSignatureNumerator: Int = 4
    var timeSignatureDenominator: Int = 4
    var duration: TimeInterval = 0
    @Binding var markers: [SectionMarker]
    var isEditMode: Bool = false
    var onAddMarker: ((Double) -> Void)?
    var zoomLevel: Int = 0

    // Color assigned per unique name
    private static let nameColors: [String: Color] = {
        let colors: [Color] = [
            .blue, .purple, .orange, .teal, .pink,
            .indigo, .mint, .cyan, .yellow, .red,
            .green, .brown, .gray, .red.opacity(0.7), .blue.opacity(0.7)
        ]
        var map: [String: Color] = [:]
        for (i, name) in SectionMarker.sectionNames.enumerated() {
            map[name] = colors[i % colors.count]
        }
        return map
    }()

    private static func colorFor(_ name: String) -> Color {
        nameColors[name] ?? .white
    }

    @State private var draggingMarkerId: UUID? = nil

    private func computeZoomScale(viewWidth: CGFloat) -> CGFloat {
        guard zoomLevel > 0, bpm > 0, duration > 0 else { return 1.0 }
        let beatDuration = 60.0 / bpm
        let measureDuration = Double(timeSignatureNumerator) * beatDuration * (4.0 / Double(timeSignatureDenominator))
        let measuresCount = duration / measureDuration
        guard measuresCount > 0 else { return 1.0 }
        let currentMeasureWidth = viewWidth / CGFloat(measuresCount)
        guard currentMeasureWidth > 0 else { return 1.0 }
        // Target: zoom 1 ≈ 30pt per measure (~5mm), zoom 2 ≈ 60pt (~1cm)
        let targetWidth: CGFloat = zoomLevel == 1 ? 30 : 60
        return max(targetWidth / currentMeasureWidth, 1.0)
    }

    private func scrollOff(viewWidth: CGFloat) -> CGFloat {
        let scale = computeZoomScale(viewWidth: viewWidth)
        let cw = viewWidth * scale
        guard zoomLevel > 0 else { return 0 }
        let fixedX = viewWidth * 0.05
        let currentX = progress * cw
        let maxOffset = cw - viewWidth
        return min(max(currentX - fixedX, 0), max(maxOffset, 0))
    }

    var body: some View {
        GeometryReader { geo in
            let viewWidth = geo.size.width
            let h = geo.size.height
            let sorted = markers.sorted { $0.position < $1.position }
            let scale = computeZoomScale(viewWidth: viewWidth)
            let contentWidth = viewWidth * scale
            let isZoomed = zoomLevel > 0
            let scrollOffset = scrollOff(viewWidth: viewWidth)

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))

                // Everything rendered in a single Canvas (no layout overflow)
                Canvas { context, size in
                    let cw = size.width * scale
                    let ox = scrollOffset

                    // Section color bands
                    for (i, marker) in sorted.enumerated() {
                        let startX = CGFloat(marker.position) * cw - ox
                        let endX = (i + 1 < sorted.count
                            ? CGFloat(sorted[i + 1].position) * cw
                            : cw) - ox
                        guard endX > 0 && startX < size.width else { continue }
                        let color = Self.colorFor(marker.name)
                        let rect = CGRect(x: max(startX, 0), y: 0, width: min(endX, size.width) - max(startX, 0), height: size.height)
                        context.fill(Path(rect), with: .color(color.opacity(0.08)))
                    }

                    // Measure grid lines + beat subdivisions
                    if bpm > 0 && duration > 0 {
                        let beatDuration = (60.0 / bpm) * (4.0 / Double(timeSignatureDenominator))
                        let measureDuration = Double(timeSignatureNumerator) * beatDuration
                        if measureDuration > 0 {
                            var t = measureDuration
                            while t < duration {
                                let x = CGFloat(t / duration) * cw - ox
                                if x > size.width { break }
                                if x >= 0 {
                                    var line = Path()
                                    line.move(to: CGPoint(x: x, y: 0))
                                    line.addLine(to: CGPoint(x: x, y: size.height))
                                    context.stroke(line, with: .color(.white.opacity(0.08)), lineWidth: 1)
                                }
                                t += measureDuration
                            }

                            if isZoomed {
                                var measureStart: Double = 0
                                while measureStart < duration {
                                    for beat in 1..<timeSignatureNumerator {
                                        let beatTime = measureStart + Double(beat) * beatDuration
                                        if beatTime >= duration { break }
                                        let x = CGFloat(beatTime / duration) * cw - ox
                                        if x > size.width { break }
                                        if x >= 0 {
                                            var line = Path()
                                            line.move(to: CGPoint(x: x, y: 0))
                                            line.addLine(to: CGPoint(x: x, y: size.height))
                                            context.stroke(line, with: .color(.white.opacity(0.04)), lineWidth: 0.5)
                                        }
                                    }
                                    measureStart += measureDuration
                                }
                            }
                        }
                    }

                    // Waveform bars (only visible range)
                    let count = levelHistory.count
                    if count > 0 {
                        let slotWidth = cw / CGFloat(count)
                        let midY = size.height / 2
                        let firstSlot = max(Int(floor(ox / slotWidth)) - 1, 0)
                        let lastSlot = min(Int(ceil((ox + size.width) / slotWidth)) + 1, count - 1)

                        if firstSlot <= lastSlot {
                            for i in firstSlot...lastSlot {
                                let level = levelHistory[i]
                                let x = CGFloat(i) * slotWidth + slotWidth / 2 - ox
                                let barH = max(CGFloat(level) * size.height * 0.9, 1)
                                let barW = max(slotWidth - 1, 1)
                                let rect = CGRect(x: x - barW / 2, y: midY - barH / 2, width: barW, height: barH)
                                let played = CGFloat(i) / CGFloat(count) <= progress
                                context.fill(
                                    Path(roundedRect: rect, cornerRadius: 1),
                                    with: .color(played ? .green : .green.opacity(0.25))
                                )
                            }
                        }
                    }

                    // Marker lines and labels
                    for marker in sorted {
                        let x = CGFloat(marker.position) * cw - ox
                        guard x > -30 && x < size.width + 30 else { continue }
                        let color = Self.colorFor(marker.name)

                        if marker.position > 0 {
                            var line = Path()
                            line.move(to: CGPoint(x: x, y: 0))
                            line.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(line, with: .color(color.opacity(0.6)), lineWidth: 1)
                        }

                        context.draw(
                            Text(marker.name)
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(color),
                            at: CGPoint(x: x + 20, y: 7),
                            anchor: .center
                        )
                    }

                    // Playhead
                    let playheadX = isZoomed ? progress * cw - ox : progress * size.width
                    let clampedPH = max(min(playheadX, size.width), 1)
                    var playLine = Path()
                    playLine.move(to: CGPoint(x: clampedPH, y: 0))
                    playLine.addLine(to: CGPoint(x: clampedPH, y: size.height))
                    context.stroke(playLine, with: .color(.white), lineWidth: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Drag handles for markers (edit mode only)
                if isEditMode {
                    ForEach(sorted, id: \.id) { marker in
                        if marker.name != "Start" {
                            let x = CGFloat(marker.position) * contentWidth - scrollOffset
                            if x > -5 && x < viewWidth + 5 {
                                Circle()
                                    .fill(Self.colorFor(marker.name))
                                    .frame(width: 10, height: 10)
                                    .shadow(color: .black.opacity(0.5), radius: 2)
                                    .position(x: x, y: h - 5)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                let newPct = min(max(Double((value.location.x + scrollOffset) / contentWidth), 0.01), 0.99)
                                                if let idx = markers.firstIndex(where: { $0.id == marker.id }) {
                                                    markers[idx].position = newPct
                                                }
                                            }
                                    )
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if isEditMode {
                    let off = scrollOff(viewWidth: viewWidth)
                    // Position computed in gesture overlay
                }
            }
            .simultaneousGesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        if isEditMode {
                            let off = scrollOff(viewWidth: viewWidth)
                            let pct = Double((value.location.x + off) / contentWidth)
                            onAddMarker?(min(max(pct, 0), 1))
                        }
                    }
            )
            .gesture(
                isPlaying || isEditMode ? nil :
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let off = scrollOff(viewWidth: viewWidth)
                        let pct = min(max((value.location.x + off) / contentWidth, 0), 1)
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
            context.stroke(path, with: .foreground, lineWidth: 1.5)
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
    @Binding var isRepeatingSection: Bool
    let onRepeatSection: () -> Void
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
    @Binding var showTimeMenu: Bool
    @Binding var showBpmMenu: Bool
    @Binding var showKeyMenu: Bool
    @Binding var markers: [SectionMarker]
    @Binding var isEditMode: Bool
    var onMarkerAdd: ((Double) -> Void)?
    var onSaveMarkers: (() -> Void)?
    @State private var zoomLevel: Int = 0
    @State private var showMarkersSaved = false

    var body: some View {
        VStack(spacing: 8) {
            // Controls
            HStack(spacing: 6) {
                // Session menu
                transportButton(icon: "line.3.horizontal") {}
                    .overlay { Menu { sessionMenuContent } label: { Color.clear } }

                Spacer()

                // Transport controls
                HStack(spacing: 6) {
                    transportButton(icon: "stop", action: onStop)
                    transportButton(icon: "backward", action: onPrev)
                    transportButton(icon: isPlaying ? "pause" : "play", action: onPlayPause)
                    transportButton(icon: "forward", action: onNext)
                }

                // Info buttons
                HStack(spacing: 6) {
                    // Fade
                    FadeIcon(mode: fadeMode)
                        .frame(width: 16, height: 12)
                        .foregroundColor(.white.opacity(0.85))
                        .opacity(isFading ? (blinkVisible ? 1.0 : 0.3) : 1.0)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture { onFadeTap() }

                    // Repeat section
                    Image(systemName: "repeat.1")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(
                            markers.isEmpty
                                ? .white.opacity(0.3)
                                : isRepeatingSection ? .orange : .white.opacity(0.85)
                        )
                        .frame(width: 32, height: 32)
                        .background(
                            markers.isEmpty
                                ? Color.white.opacity(0.05)
                                : isRepeatingSection ? Color.orange.opacity(0.2) : Color.white.opacity(0.1)
                        )
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !markers.isEmpty else { return }
                            onRepeatSection()
                        }

                    // Time
                    Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(height: 32)
                        .padding(.horizontal, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showBpmMenu = false
                            showKeyMenu = false
                            showTimeMenu.toggle()
                        }

                    // BPM
                    Text("\(Int(bpm))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(bpm != originalBpm ? .orange : .white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showTimeMenu = false
                            showKeyMenu = false
                            showBpmMenu.toggle()
                        }

                    // Key
                    Text(musicalKey)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(musicalKey != originalKey ? .orange : .white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showTimeMenu = false
                            showBpmMenu = false
                            showKeyMenu.toggle()
                        }
                }

                Spacer()

                // Edit mode
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isEditMode ? .orange : .white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(isEditMode ? Color.orange.opacity(0.2) : Color.white.opacity(0.1))
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditMode.toggle()
                        if isEditMode && markers.isEmpty {
                            markers.append(SectionMarker(name: "Start", position: 0))
                        }
                    }

                // Save markers (visible when markers exist)
                if !markers.isEmpty {
                    Image(systemName: showMarkersSaved ? "checkmark" : "square.and.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(showMarkersSaved ? .green : .white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(showMarkersSaved ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSaveMarkers?()
                            showMarkersSaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showMarkersSaved = false
                            }
                        }
                }

                // Settings
                transportButton(icon: "gearshape", action: onSettingsTap)
            }
            .padding(.horizontal)

            // Waveform progress bar + zoom button
            HStack(spacing: 6) {
                WaveformBar(
                    progress: duration > 0 ? CGFloat(currentTime / duration) : 0,
                    levelHistory: levelHistory,
                    isPlaying: isPlaying,
                    onSeek: { pct in
                        let seekTime = Double(pct) * maxDuration
                        startOffset = seekTime
                        onSeek(seekTime)
                    },
                    bpm: bpm,
                    timeSignatureNumerator: timeSignatureNumerator,
                    timeSignatureDenominator: timeSignatureDenominator,
                    duration: maxDuration,
                    markers: $markers,
                    isEditMode: isEditMode,
                    onAddMarker: { position in
                        onMarkerAdd?(position)
                    },
                    zoomLevel: zoomLevel
                )
                .frame(height: 44)

                // Zoom button at waveform level
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(zoomLevel > 0 ? .orange : .white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(zoomLevel > 0 ? Color.orange.opacity(0.2) : Color.white.opacity(0.1))
                    .cornerRadius(6)
                    .overlay(
                        zoomLevel > 0 ?
                            Text("\(zoomLevel)")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.orange)
                                .offset(x: 10, y: 10)
                            : nil
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        zoomLevel = (zoomLevel + 1) % 3
                    }
            }
            .padding(.horizontal)

        }
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
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

    private func transportButton(icon: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
        }
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
    @State private var bpmText: String = ""

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

                TextField("120", text: $bpmText)
                    .font(.system(.body, design: .monospaced).bold())
                    .frame(width: 50)
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                    .onAppear { bpmText = "\(Int(bpm))" }
                    .onChange(of: bpmText) { _ in
                        if let val = Double(bpmText), val >= 20, val <= 300 {
                            bpm = val
                        }
                    }
                    .onChange(of: bpm) { _ in
                        let newText = "\(Int(bpm))"
                        if bpmText != newText { bpmText = newText }
                    }

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

