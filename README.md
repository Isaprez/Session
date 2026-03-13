# Session

App iOS para mezcla de audio multitrack en vivo. Diseñada para músicos que necesitan reproducir y mezclar pistas de audio en tiempo real durante presentaciones en vivo.

## Funcionalidades

### Reproductor Multitrack
- Importa carpetas con archivos de audio (WAV, MP3, M4A, AIF, AIFF, CAF)
- Reproducción sincronizada de múltiples pistas usando AVAudioEngine
- Controles de transporte: play/pause, stop, siguiente/anterior sesión

### Mixer
- Fader de volumen por pista con indicador de nivel en tiempo real (RMS)
- Fader Master fijo a la izquierda
- Botones de Mute (M) y Solo (S) por pista
- Detección automática de pistas especiales (Click y Cues) con color púrpura
- Scroll horizontal para navegar entre pistas
- EQ paramétrico de 5 bandas por pista (60Hz, 250Hz, 1kHz, 4kHz, 12kHz)

### Barra de Transporte
- Visualización de waveform pre-computado de todas las pistas
- Playhead arrastrable cuando la reproducción está detenida
- Controles de tiempo: inicio, fin y auto-fade configurables
- Navegación entre sesiones (anterior/siguiente)

### Tempo y Tono
- Control de BPM (20-300) con cambio de velocidad sin afectar el tono
- Cambio de tono entre las 12 notas musicales (C, C#, D... B) sin afectar la velocidad
- Signatura de compás configurable (ej. 4/4, 3/4, 6/8)
- Al importar una sesión se solicitan BPM, compás y tono original
- Usa AVAudioUnitTimePitch para procesamiento en tiempo real

### Fade In/Out
- Fade out e in manual con duración configurable (0-30 segundos)
- Auto-fade en un tiempo específico de la canción
- Indicador visual con parpadeo durante el fade
- Icono de triángulo que indica la dirección del fade

### Gestión de Sesiones
- Importación de carpetas desde el sistema de archivos
- Múltiples sesiones con cambio rápido
- Eliminación de sesiones
- Menú hamburguesa para acceso rápido

## Arquitectura

```
Session/
├── SessionApp.swift              # Entry point, landscape lock
├── ContentView.swift             # Vista principal y gestión de sesiones
├── Audio/
│   └── AudioEngineManager.swift  # Motor de audio (AVAudioEngine)
├── Models/
│   ├── Session.swift             # Modelo de sesión
│   └── Track.swift               # Modelo de pista y EQ
└── Views/
    ├── SettingsView.swift         # Configuración general
    ├── SessionListView.swift      # Importador de carpetas
    └── Components/
        ├── TransportBar.swift     # Barra de transporte, waveform, popovers
        ├── TrackRowView.swift     # Channel strips (Master + Tracks)
        └── EQView.swift           # Editor de EQ por pista
```

### Stack Tecnológico
- **SwiftUI** - Interfaz de usuario
- **AVAudioEngine** - Procesamiento de audio multitrack
- **AVAudioUnitTimePitch** - Cambio de tempo y tono en tiempo real
- **AVAudioUnitEQ** - Ecualización paramétrica
- **CADisplayLink** - Tracking de tiempo de reproducción
- **Canvas** - Renderizado de waveform e iconos custom

## Requisitos
- iOS 16.0+
- Xcode 14+
- Orientación landscape obligatoria

## Uso
1. Abre la app y selecciona "Importar Carpeta"
2. Elige una carpeta que contenga los archivos de audio multitrack
3. Configura el BPM, compás y tono de la sesión
4. Usa los faders para mezclar las pistas en tiempo real
5. Controla la reproducción con la barra de transporte
