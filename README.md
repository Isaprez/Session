# Session

App iOS para mezcla de audio multitrack en vivo. Diseñada para músicos que necesitan reproducir y mezclar pistas de audio en tiempo real durante presentaciones en vivo.

## Funcionalidades

### Reproductor Multitrack
- Importa carpetas con archivos de audio (WAV, MP3, M4A, AIF, AIFF, CAF)
- Reproducción sincronizada de múltiples pistas usando AVAudioEngine
- Controles de transporte: play/pause, stop, siguiente/anterior sesión
- Nombre de la pista actual visible junto al botón de sesiones

### Mixer
- Fader de volumen por pista con indicador de nivel en tiempo real (RMS con vDSP)
- Fader Master fijo a la izquierda
- Botones de Mute (M) y Solo (S) por pista
- Detección automática de pistas especiales (Click y Cues) con color púrpura
- Nombres normalizados: archivos de click/clic siempre muestran "Click", archivos de cue/guía siempre muestran "Cues"
- Scroll horizontal para navegar entre pistas
- EQ paramétrico de 5 bandas por pista (60Hz, 250Hz, 1kHz, 4kHz, 12kHz)
- Paneo (pan) por pista

### Barra de Transporte
- Visualización de waveform pre-computado con 3 niveles de resolución adaptativa
- Escala logarítmica (dB) para waveform más expresivo
- Playhead arrastrable cuando la reproducción está detenida (sin afectar configuración de tiempo)
- Controles de tiempo: inicio, fin y auto-fade configurables
- Navegación entre sesiones (anterior/siguiente)
- Líneas de compás basadas en BPM original y signatura de tiempo (no se deforman al cambiar tempo)

### Alineación de Grilla (Grid Offset)
- Detección automática del offset de grilla al importar una sesión
- Si hay click track: detecta el acento (beat 1) analizando transientes y amplitudes
- Medición automática de BPM real desde los intervalos del click
- Corrección automática de BPM doble/mitad (ej. si detecta 255 en vez de 128, corrige a 127.5)
- Slider manual de ajuste fino (0-5s, paso de 0.01s) en Configuración > General > Grilla
- Botón "Detectar Automáticamente" con indicador de carga y palomita de confirmación
- Se guarda por sesión en `session_config.json`

### Zoom de Waveform
- 3 niveles de zoom con resolución progresiva:
  - Zoom 0 (normal): 400 slots — carga rápida
  - Zoom 1: 1200 slots — detalle medio
  - Zoom 2: 3600 slots — máximo detalle
- Resolución se genera progresivamente (vista rápida primero, detalle en segundo plano)
- Al hacer zoom, el playhead se fija en el borde izquierdo y el waveform se desplaza
- Scroll manual al arrastrar cuando está en zoom, con retorno automático a los 3 segundos
- Líneas de subdivisión por beat cuando el zoom está activo
- Botón de zoom junto al waveform con indicador de nivel activo
- Solo se renderiza el contenido visible para optimizar rendimiento
- Indicador de carga (ProgressView) mientras se genera el waveform

### Marcadores de Sección
- Modo de edición con botón de lápiz
- Doble tap para agregar marcadores en cualquier punto del waveform
- Selector centrado con todas las secciones: Start, Intro, Verso, Pre-coro, Coro, Puente, Solo, Interludio, Breakdown, Build, Drop, Outro
- Marcadores arrastrables para ajustar posición exacta
- Colores consistentes por nombre de sección (mismo nombre = mismo color)
- Se permiten etiquetas duplicadas
- Bandas de color de fondo por sección en el waveform
- Botón de guardar marcadores (solo visible en modo edición)

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
- Renombrar carpeta de sesión al importar
- Usa AVAudioUnitTimePitch para procesamiento en tiempo real

### Fade In/Out
- Fade out e in manual con duración configurable (0-30 segundos)
- Auto-fade en un tiempo específico de la canción
- Indicador visual con parpadeo durante el fade
- Icono outlined de triángulo que indica la dirección del fade

### Modos de Transición
- 6 modos de transición configurables por sesión:
  - **Stop**: la reproducción se detiene al terminar
  - **Advance**: se detiene y pasa a la siguiente sesión (sin reproducir)
  - **Auto Advance**: pasa a la siguiente sesión y reproduce automáticamente
  - **Crossfade**: mezcla gradual entre sesión actual y siguiente
  - **Overlap**: reproduce ambas sesiones simultáneamente durante la transición
  - **Trigger**: modo armado, espera acción manual para avanzar
- Duración de transición configurable (0-30 segundos, aplica a Crossfade y Overlap)
- Modo de transición visible y editable desde el menú de sesiones

### Gestión de Sesiones
- Importación de carpetas desde el sistema de archivos
- Múltiples sesiones con cambio rápido
- Menú popover de sesiones con:
  - Info por sesión (compás, BPM, tono)
  - Selector de modo de transición por sesión
  - Eliminación con confirmación
  - Reordenamiento por arrastrar (long press)
- Nombre de sesión actual visible en la barra de transporte

### Configuración (Panel Lateral)
- Menú de configuración con panel lateral dividido en secciones:
  - **General**: Fade, Grilla (offset + detección automática), Transición, Guardar/Compartir
  - **Paneo**: Control L/R por pista con indicador de modificación
  - **EQ**: Ecualizador por pista con indicador de modificación
- Indicadores visuales (punto naranja) cuando paneo o EQ han sido modificados

### Persistencia y Compartir
- Archivo `session_config.json` por sesión dentro de cada carpeta
- Se crea automáticamente si no existe al cargar la sesión
- **Marcadores**: se guardan con botón dedicado junto al modo edición
- **Guardar Pista Actual**: guarda BPM, tono, signatura, volúmenes, pan, mute/solo, EQ por pista, tiempos de inicio/fin, auto-fade, fade duration, volumen master, modo de transición, grid offset
- **Compartir Pista Actual**: exporta la carpeta de la sesión actual como ZIP
- **Compartir Sesión Completa**: exporta todas las sesiones cargadas en un único ZIP (al descomprimir se conservan todas las carpetas)
- Al abrir una sesión se restauran todos los valores guardados

## Arquitectura

```
Session/
├── SessionApp.swift              # Entry point, landscape lock
├── ContentView.swift             # Vista principal y gestión de sesiones
├── Audio/
│   └── AudioEngineManager.swift  # Motor de audio (AVAudioEngine + Accelerate)
├── Models/
│   ├── Session.swift             # Modelo de sesión
│   ├── Track.swift               # Modelo de pista, EQ y marcadores de sección
│   ├── SessionConfig.swift       # Modelo Codable de persistencia (JSON)
│   └── TransitionMode.swift      # Enum de 6 modos de transición
└── Views/
    ├── SettingsView.swift         # Panel lateral de configuración + compartir
    └── Components/
        └── TransportBar.swift     # Barra de transporte, waveform, zoom, popovers, menú de sesiones
```

### Stack Tecnológico
- **SwiftUI** - Interfaz de usuario
- **AVAudioEngine** - Procesamiento de audio multitrack
- **AVAudioUnitTimePitch** - Cambio de tempo y tono en tiempo real
- **AVAudioUnitEQ** - Ecualización paramétrica
- **Accelerate (vDSP)** - Cálculo RMS optimizado para waveform y metering
- **CADisplayLink** - Tracking de tiempo de reproducción
- **Canvas** - Renderizado de waveform, grid, marcadores e iconos custom
- **Codable/JSON** - Persistencia de configuración por sesión
- **NSFileCoordinator** - Compresión ZIP para compartir sesiones

## Requisitos
- iOS 16.0+
- Xcode 14+
- Orientación landscape obligatoria

## Uso
1. Abre la app y selecciona "Importar Carpeta"
2. Elige una carpeta que contenga los archivos de audio multitrack
3. Configura el BPM, compás y tono de la sesión (opcionalmente renombra la carpeta)
4. Usa los faders para mezclar las pistas en tiempo real
5. Controla la reproducción con la barra de transporte
6. Usa el modo edición (lápiz) para agregar marcadores de sección
7. Guarda los marcadores con el botón de descarga
8. Configura modos de transición por sesión desde el menú de sesiones
9. Guarda configuración desde Configuración > General > Guardar Pista Actual
10. Comparte sesiones individuales o todas juntas desde Configuración > General
