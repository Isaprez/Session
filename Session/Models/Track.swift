import Foundation

struct Track: Identifiable {
    let id = UUID()
    let name: String
    let fileURL: URL
    var volume: Float = 1.0
    var pan: Float = 0.0
    var isMuted: Bool = false
    var isSolo: Bool = false
    var eqBands: [EQBand] = EQBand.defaultBands

    var displayName: String {
        let filename = fileURL.deletingPathExtension().lastPathComponent
        return filename
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    var isClick: Bool {
        name.lowercased().contains("click")
    }

    var isCues: Bool {
        name.lowercased().contains("cue")
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
