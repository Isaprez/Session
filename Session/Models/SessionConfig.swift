import Foundation

struct SessionConfig: Codable {
    // Session metadata
    var bpm: Double
    var timeSignatureNumerator: Int
    var timeSignatureDenominator: Int
    var musicalKey: String

    // Time controls
    var startOffset: Double
    var endTime: Double
    var autoFadeAt: Double
    var fadeDuration: Float

    // Master
    var masterVolume: Float

    // Track settings (keyed by track filename)
    var trackSettings: [TrackConfig]

    // Section markers
    var markers: [MarkerConfig]

    struct TrackConfig: Codable {
        var filename: String
        var volume: Float
        var pan: Float
        var isMuted: Bool
        var isSolo: Bool
        var eqGains: [Float] // 5 bands
    }

    struct MarkerConfig: Codable {
        var name: String
        var position: Double
    }

    // MARK: - File path

    static func configURL(for folderURL: URL) -> URL {
        folderURL.appendingPathComponent("session_config.json")
    }

    // MARK: - Save

    func save(to folderURL: URL) {
        let url = Self.configURL(for: folderURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Load

    static func load(from folderURL: URL) -> SessionConfig? {
        let url = configURL(for: folderURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionConfig.self, from: data)
    }

    // MARK: - Save only markers

    static func saveMarkers(_ markers: [SectionMarker], to folderURL: URL) {
        var config = load(from: folderURL) ?? SessionConfig.defaultConfig()
        config.markers = markers.map { MarkerConfig(name: $0.name, position: $0.position) }
        config.save(to: folderURL)
    }

    // MARK: - Default

    static func defaultConfig() -> SessionConfig {
        SessionConfig(
            bpm: 120,
            timeSignatureNumerator: 4,
            timeSignatureDenominator: 4,
            musicalKey: "C",
            startOffset: 0,
            endTime: 0,
            autoFadeAt: 0,
            fadeDuration: 10,
            masterVolume: 1.0,
            trackSettings: [],
            markers: []
        )
    }
}
