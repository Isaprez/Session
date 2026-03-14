import Foundation

// MARK: - Song Section Marker

struct SectionMarker: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var position: Double // 0...1 percentage of total duration

    static let sectionNames = [
        "Start", "Intro", "Verso 1", "Verso 2", "Verso 3",
        "Pre-coro", "Coro", "Coro 2", "Puente", "Solo",
        "Interludio", "Breakdown", "Build", "Drop", "Outro"
    ]
}

struct Track: Identifiable {
    let id = UUID()
    let name: String
    var fileURL: URL
    var volume: Float = 1.0
    var pan: Float = 0.0
    var isMuted: Bool = false
    var isSolo: Bool = false
    var eqBands: [EQBand] = EQBand.defaultBands

    var displayName: String {
        if isClick { return "Click" }
        if isCues { return "Cues" }
        let filename = fileURL.deletingPathExtension().lastPathComponent
        return filename
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    var isClick: Bool {
        let lower = name.lowercased()
        return lower.contains("click") || lower.contains("clic")
    }

    var isCues: Bool {
        let lower = name.lowercased()
        return lower.contains("cue") || lower.contains("guia") || lower.contains("guía")
    }

    var isSpecial: Bool {
        isClick || isCues
    }
}

struct EQBand: Identifiable {
    let id = UUID()
    var frequency: Float
    var gain: Float
    var bandwidth: Float
    var label: String

    static let defaultBands: [EQBand] = [
        EQBand(frequency: 60, gain: 0, bandwidth: 1.0, label: "60 Hz"),
        EQBand(frequency: 250, gain: 0, bandwidth: 1.0, label: "250 Hz"),
        EQBand(frequency: 1000, gain: 0, bandwidth: 1.0, label: "1 kHz"),
        EQBand(frequency: 4000, gain: 0, bandwidth: 1.0, label: "4 kHz"),
        EQBand(frequency: 12000, gain: 0, bandwidth: 1.0, label: "12 kHz")
    ]
}
