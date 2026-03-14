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
- Visualización de waveform pre-computado (excluye pistas de click) con alta resolución (1200 slots)
- Escala logarítmica (dB) para waveform más expresivo
- Playhead arrastrable cuando la reproducción está detenida
- Controles de tiempo: inicio, fin y auto-fade configurables
- Navegación entre sesiones (anterior/siguiente)
- Líneas de compás basadas en BPM y signatura de tiempo

### Zoom de Waveform
- 3 niveles de zoom: normal, zoom 1 (~5mm por compás), zoom 2 (~1cm por compás)
- Al hacer zoom, el playhead se fija en el borde izquierdo y el waveform se desplaza
- Líneas de subdivisión por beat cuando el zoom está activo (para 4/4 u otra signatura)
- Botón de zoom junto al waveform con indicador de nivel activo
- Solo se renderiza el contenido visible para optimizar rendimiento

### Marcadores de Sección
- Modo de edición con botón de lápiz
- Doble tap para agregar marcadores en cualquier punto del waveform
- Selector centrado con todas las secciones: Start, Intro, Verso, Pre-coro, Coro, Puente, Solo, Interludio, Breakdown, Build, Drop, Outro
- Marcadores arrastrables para ajustar posición exacta
- Colores consistentes por nombre de sección (mismo nombre = mismo color)
- Se permiten etiquetas duplicadas
- Bandas de color de fondo por sección en el waveform
- Botón de guardar marcadores independiente

### Repetición de Sección
- Botón de repetir (repeat.1) junto al fade
- Detecta automáticamente la sección actual basándose en los marcadores
- Al activarse, repite la sección una vez y se desactiva automáticamente
- Se puede reactivar cuantas veces se necesite
- Deshabilitado cuando no hay marcadores

### Tempo y Tono
- Control de BPM (20-300) con campo editable y botones +/-
- Cambio de tono entre las 12 notas musicales sin afectar la velocidad
- Signatura de compás configurable (ej. 4/4, 3/4, 6/8)
- Al importar una sesión se solicitan BPM, compás y tono original
- Usa AVAudioUnitTimePitch para procesamiento en tiempo real

### Fade In/Out
- Fade out e in manual con duración configurable (0-30 segundos)
- Auto-fade en un tiempo específico de la canción
- Indicador visual con parpadeo durante el fade
- Icono outlined de triángulo que indica la dirección del fade

### Persistencia y Configuración
- Archivo `session_config.json` por sesión dentro de cada carpeta
- Se crea automáticamente si no existe al cargar la sesión
- **Marcadores**: se guardan con botón dedicado junto al modo edición
- **Sesión completa** (desde Configuración > Guardar Sesión): guarda BPM, tono, signatura, volúmenes, pan, mute/solo, EQ por pista, tiempos de inicio/fin, auto-fade, fade duration, volumen master
- Al abrir una sesión se restauran todos los valores guardados
- Configuración inicial se guarda automáticamente al importar

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
│   ├── Track.swift               # Modelo de pista, EQ y marcadores de sección
│   └── SessionConfig.swift       # Modelo Codable de persistencia (JSON)
└── Views/
    ├── SettingsView.swift         # Configuración general + guardar sesión
    ├── SessionListView.swift      # Importador de carpetas
    └── Components/
        ├── TransportBar.swift     # Barra de transporte, waveform, zoom, popovers
        ├── TrackRowView.swift     # Channel strips (Master + Tracks)
        └── EQView.swift           # Editor de EQ por pista
```

### Stack Tecnológico
- **SwiftUI** - Interfaz de usuario
- **AVAudioEngine** - Procesamiento de audio multitrack
- **AVAudioUnitTimePitch** - Cambio de tempo y tono en tiempo real
- **AVAudioUnitEQ** - Ecualización paramétrica
- **CADisplayLink** - Tracking de tiempo de reproducción
- **Canvas** - Renderizado de waveform, grid, marcadores e iconos custom
- **Codable/JSON** - Persistencia de configuración por sesión

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
6. Usa el modo edición (lápiz) para agregar marcadores de sección
7. Guarda los marcadores con el botón de descarga
8. Guarda toda la configuración desde Configuración > Guardar Sesión
