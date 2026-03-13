import SwiftUI

struct LevelMeterView: View {
    var level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.1))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green)
                    .frame(height: geo.size.height * CGFloat(level))
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
        .cornerRadius(2)
    }
}

struct MasterStripView: View {
    @Binding var volume: Float
    var level: Float = 0

    var body: some View {
        VStack(spacing: 8) {
            Text("Master")
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.bold)
                .frame(width: 70, height: 32)

            // Fader + Level meter (uses full remaining height, no spacer)
            HStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green.opacity(0.7))
                            .frame(height: geo.size.height * CGFloat(volume))
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let newValue = 1.0 - Float(value.location.y / geo.size.height)
                                volume = min(max(newValue, 0), 1)
                            }
                    )
                }
                .frame(width: 50)
                .cornerRadius(4)

                LevelMeterView(level: level)
                    .frame(width: 6)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(width: 80)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(10)
        .padding(.leading, 8)
        .padding(.vertical, 8)
    }
}

struct TrackStripView: View {
    @Binding var track: Track
    var level: Float = 0
    let onVolumeChange: (Float) -> Void
    let onMuteToggle: () -> Void
    let onSoloToggle: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Track name
            Text(track.displayName)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 70, height: 32)

            // Fader + Level meter
            HStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(track.isSpecial ? Color.purple.opacity(0.7) : Color.accentColor.opacity(0.7))
                            .frame(height: geo.size.height * CGFloat(track.volume))
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let newValue = 1.0 - Float(value.location.y / geo.size.height)
                                track.volume = min(max(newValue, 0), 1)
                                onVolumeChange(track.volume)
                            }
                    )
                }
                .frame(width: 50)
                .cornerRadius(4)

                LevelMeterView(level: level)
                    .frame(width: 6)
            }

            // Mute & Solo buttons
            HStack(spacing: 4) {
                Button(action: {
                    track.isMuted.toggle()
                    onMuteToggle()
                }) {
                    Text("M")
                        .font(.system(.caption2, design: .rounded).bold())
                        .frame(width: 28, height: 28)
                        .background(track.isMuted ? Color.red : Color.secondary.opacity(0.2))
                        .foregroundColor(track.isMuted ? .white : .primary)
                        .cornerRadius(6)
                }

                Button(action: {
                    track.isSolo.toggle()
                    onSoloToggle()
                }) {
                    Text("S")
                        .font(.system(.caption2, design: .rounded).bold())
                        .frame(width: 28, height: 28)
                        .background(track.isSolo ? Color.yellow : Color.secondary.opacity(0.2))
                        .foregroundColor(track.isSolo ? .black : .primary)
                        .cornerRadius(6)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(width: 80)
        .background(track.isSpecial ? Color.purple.opacity(0.1) : Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}
