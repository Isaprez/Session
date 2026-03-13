import SwiftUI

struct EQView: View {
    @Binding var track: Track
    let onEQChange: ([EQBand]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text(track.displayName)
                    .font(.headline)
                    .padding(.top)

                // EQ Bands
                VStack(spacing: 24) {
                    ForEach(track.eqBands.indices, id: \.self) { index in
                        EQBandRow(band: $track.eqBands[index]) {
                            onEQChange(track.eqBands)
                        }
                    }
                }
                .padding()

                // Reset button
                Button(action: resetEQ) {
                    Label("Resetear EQ", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(8)
                }

                Spacer()
            }
            .navigationTitle("Ecualizador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    private func resetEQ() {
        track.eqBands = EQBand.defaultBands
        onEQChange(track.eqBands)
    }
}

struct EQBandRow: View {
    @Binding var band: EQBand
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(band.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)

                Slider(value: $band.gain, in: -12...12, step: 0.5) { _ in
                    onChange()
                }
                .tint(band.gain >= 0 ? .green : .red)

                Text(String(format: "%+.1f dB", band.gain))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }
}
