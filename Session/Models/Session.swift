import Foundation

struct MusicSession: Identifiable {
    let id = UUID()
    var name: String
    var folderURL: URL
    var tracks: [Track]
    var bpm: Double = 120
    var timeSignatureNumerator: Int = 4
    var timeSignatureDenominator: Int = 4
    var musicalKey: String = "C"

    static let supportedExtensions = ["wav", "mp3", "m4a", "aif", "aiff", "caf"]

    static func load(from folderURL: URL) -> MusicSession? {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let audioFiles = files.filter { url in
            supportedExtensions.contains(url.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !audioFiles.isEmpty else { return nil }

        let tracks = audioFiles.map { Track(name: $0.deletingPathExtension().lastPathComponent, fileURL: $0) }
        let name = folderURL.lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        return MusicSession(name: name, folderURL: folderURL, tracks: tracks)
    }
}
