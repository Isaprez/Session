import Foundation

enum TransitionMode: String, Codable, CaseIterable {
    case stop
    case advance
    case autoAdvance
    case crossfade
    case overlap
    case trigger

    var displayName: String {
        switch self {
        case .stop: return "Stop"
        case .advance: return "Advance"
        case .autoAdvance: return "Auto Advance"
        case .crossfade: return "Crossfade"
        case .overlap: return "Overlap"
        case .trigger: return "Trigger"
        }
    }

    var icon: String {
        switch self {
        case .stop: return "stop.circle"
        case .advance: return "forward.end"
        case .autoAdvance: return "forward.end.fill"
        case .crossfade: return "arrow.triangle.swap"
        case .overlap: return "square.2.layers.3d"
        case .trigger: return "bolt.circle"
        }
    }

    var description: String {
        switch self {
        case .stop: return "La pista se detiene al final"
        case .advance: return "Carga la siguiente sin reproducir"
        case .autoAdvance: return "Reproduce la siguiente automáticamente"
        case .crossfade: return "Mezcla con fade entre sesiones"
        case .overlap: return "Superpone ambas a volumen completo"
        case .trigger: return "Arma la siguiente, espera tu señal"
        }
    }
}
