# LaunchNext

**Idiomas**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 Descargar

**[Descargar aquí](https://github.com/RoversX/LaunchNext/releases/latest)** - Obtén la última versión

⭐ ¡Considera dar una estrella a [LaunchNext](https://github.com/RoversX/LaunchNext) y especialmente al proyecto original [LaunchNow](https://github.com/ggkevinnnn/LaunchNow)!

| | |
|:---:|:---:|
| ![](../public/banner.webp) | ![](../public/setting1.webp) |
| ![](../public/setting2.webp) | ![](../public/setting3.webp) |

macOS Tahoe eliminó el Launchpad, y la nueva interfaz es difícil de usar, no aprovecha completamente tu Bio GPU. Apple, al menos da a los usuarios una opción para volver atrás. Mientras tanto, aquí está LaunchNext.

*Construido sobre [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) por ggkevinnnn — ¡muchísimas gracias al proyecto original!❤️*

*LaunchNow ha elegido la licencia GPL 3. LaunchNext sigue los mismos términos de licencia.*

⚠️ **Si macOS bloquea la aplicación, ejecute esto en Terminal:**
```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNext.app
```
**Por qué**: No puedo permitirme el certificado de desarrollador de Apple ($99/año), por lo que macOS bloquea aplicaciones sin firmar. Este comando elimina la bandera de cuarentena para permitir que se ejecute. **Use este comando solo en aplicaciones de confianza.**

### Lo que LaunchNext ofrece
- ✅ **Importación con un clic desde el Launchpad del sistema antiguo** - lee directamente tu base de datos SQLite nativa de Launchpad (`/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db`) para recrear perfectamente tus carpetas existentes, posiciones de aplicaciones y diseño
- ✅ **Experiencia clásica de Launchpad** - funciona exactamente como la interfaz original querida
- ✅ **Soporte multi-idioma** - internacionalización completa con inglés, chino, japonés, francés y español
- ✅ **Ocultar etiquetas de iconos** - vista limpia y minimalista cuando no necesitas nombres de aplicaciones
- ✅ **Tamaños de iconos personalizados** - ajusta las dimensiones de los iconos según tus preferencias
- ✅ **Gestión inteligente de carpetas** - crea y organiza carpetas como antes
- ✅ **Búsqueda instantánea y navegación por teclado** - encuentra aplicaciones rápidamente

### Lo que perdimos en macOS Tahoe
- ❌ Sin organización personalizada de aplicaciones
- ❌ Sin carpetas creadas por el usuario
- ❌ Sin personalización por arrastrar y soltar
- ❌ Sin gestión visual de aplicaciones
- ❌ Agrupación categórica forzada

## Características

### 🎯 **Lanzamiento instantáneo de aplicaciones**
- Doble clic para lanzar aplicaciones directamente
- Soporte completo de navegación por teclado
- Búsqueda ultrarrápida con filtrado en tiempo real

### 📁 **Sistema de carpetas avanzado**
- Crear carpetas arrastrando aplicaciones juntas
- Renombrar carpetas con edición en línea
- Iconos de carpetas personalizados y organización
- Arrastrar aplicaciones dentro y fuera sin problemas

### 🔍 **Búsqueda inteligente**
- Coincidencia difusa en tiempo real
- Buscar en todas las aplicaciones instaladas
- Atajos de teclado para acceso rápido

### 🎨 **Diseño de interfaz moderna**
- **Efecto cristal líquido**: regularMaterial con sombras elegantes
- Modos de visualización en pantalla completa y ventana
- Animaciones y transiciones suaves
- Diseño limpio y responsivo

### 🔄 **Migración de datos sin problemas**
- **Importación de Launchpad con un clic** desde la base de datos nativa de macOS
- Descubrimiento y escaneo automático de aplicaciones
- Almacenamiento persistente de diseño vía SwiftData
- Cero pérdida de datos durante actualizaciones del sistema

### ⚙️ **Integración del sistema**
- Aplicación nativa de macOS
- Posicionamiento inteligente multi-pantalla
- Funciona junto con Dock y otras aplicaciones del sistema
- Detección de clics de fondo (cierre inteligente)

## Arquitectura técnica

### Construido con tecnologías modernas
- **SwiftUI**: Marco de interfaz de usuario declarativo y eficiente
- **SwiftData**: Capa robusta de persistencia de datos
- **AppKit**: Integración profunda del sistema macOS
- **SQLite3**: Lectura directa de base de datos Launchpad

### Almacenamiento de datos
Los datos de la aplicación se almacenan de forma segura en:
```
~/Library/Application Support/LaunchNext/Data.store
```

### Integración nativa de Launchpad
Lee directamente desde la base de datos del sistema Launchpad:
```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Instalación

### Requisitos
- macOS 26 (Tahoe) o posterior
- Procesador Apple Silicon o Intel
- Xcode 26 (para compilar desde fuente)

### Compilar desde fuente

1. **Clonar el repositorio**
   ```bash
   git clone https://github.com/yourusername/LaunchNext.git
   cd LaunchNext/LaunchNext
   ```

2. **Abrir en Xcode**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **Compilar y ejecutar**
   - Seleccionar tu dispositivo objetivo
   - Presionar `⌘+R` para compilar y ejecutar
   - O `⌘+B` para solo compilar

### Compilación por línea de comandos
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

## Uso

### Primeros pasos
1. **Primer lanzamiento**: LaunchNext escanea automáticamente todas las aplicaciones instaladas
2. **Seleccionar**: Hacer clic para seleccionar aplicaciones, doble clic para lanzar
3. **Buscar**: Escribir para filtrar aplicaciones instantáneamente
4. **Organizar**: Arrastrar aplicaciones para crear carpetas y diseños personalizados

### Importar tu Launchpad
1. Abrir configuraciones (icono de engranaje)
2. Hacer clic en **"Import Launchpad"**
3. Tu diseño y carpetas existentes se importarán automáticamente

### Gestión de carpetas
- **Crear carpeta**: Arrastrar una aplicación sobre otra
- **Renombrar carpeta**: Hacer clic en el nombre de la carpeta
- **Añadir aplicaciones**: Arrastrar aplicaciones a las carpetas
- **Eliminar aplicaciones**: Arrastrar aplicaciones fuera de las carpetas

### Modos de visualización
- **Ventana**: Ventana flotante con esquinas redondeadas
- **Pantalla completa**: Modo de pantalla completa para máxima visibilidad
- Cambiar modos en configuraciones

## Problemas conocidos

> **Estado actual de desarrollo**
> - 🔄 **Comportamiento de desplazamiento**: Puede ser inestable en ciertos escenarios, especialmente con gestos rápidos
> - 🎯 **Creación de carpetas**: La detección de colisión de arrastrar y soltar para crear carpetas es a veces inconsistente
> - 🛠️ **Desarrollo activo**: Estos problemas están siendo abordados activamente en próximas versiones

## Solución de problemas

### Problemas comunes

**P: ¿La aplicación no inicia?**
R: Asegúrate de tener macOS 26+ y verifica los permisos del sistema.

**P: ¿Falta el botón de importación?**
R: Verifica que SettingsView.swift incluya la funcionalidad de importación.

**P: ¿La búsqueda no funciona?**
R: Intenta volver a escanear aplicaciones o restablecer datos de aplicación en configuraciones.

**P: ¿Problemas de rendimiento?**
R: Verifica la configuración de caché de iconos y reinicia la aplicación.

## ¿Por qué elegir LaunchNext?

### Vs la interfaz "Applications" de Apple
| Característica | Applications (Tahoe) | LaunchNext |
|---------|---------------------|------------|
| Organización personalizada | ❌ | ✅ |
| Carpetas de usuario | ❌ | ✅ |
| Arrastrar y soltar | ❌ | ✅ |
| Gestión visual | ❌ | ✅ |
| Importar datos existentes | ❌ | ✅ |
| Rendimiento | Lento | Rápido |

### Vs otras alternativas de Launchpad
- **Integración nativa**: Lectura directa de base de datos Launchpad
- **Arquitectura moderna**: Construido con SwiftUI/SwiftData más recientes
- **Cero dependencias**: Swift puro, sin bibliotecas externas
- **Desarrollo activo**: Actualizaciones y mejoras regulares
- **Diseño cristal líquido**: Efectos visuales premium

## Contribución

¡Damos la bienvenida a las contribuciones! Por favor:

1. Hacer fork del repositorio
2. Crear una rama de característica (`git checkout -b feature/amazing-feature`)
3. Hacer commit de los cambios (`git commit -m 'Add amazing feature'`)
4. Hacer push a la rama (`git push origin feature/amazing-feature`)
5. Abrir un Pull Request

### Directrices de desarrollo
- Seguir las convenciones de estilo de Swift
- Añadir comentarios significativos para lógica compleja
- Probar en múltiples versiones de macOS
- Mantener compatibilidad hacia atrás

## El futuro de la gestión de aplicaciones

Mientras Apple se aleja de las interfaces personalizables, LaunchNext representa el compromiso de la comunidad con el control del usuario y la personalización. Creemos que los usuarios deberían decidir cómo organizar su espacio de trabajo digital.

**LaunchNext** no es solo un reemplazo de Launchpad—es una declaración de que la elección del usuario importa.


---

**LaunchNext** - Recupera tu lanzador de aplicaciones 🚀

*Construido para usuarios de macOS que se niegan a comprometer en personalización.*

## Herramientas de desarrollo

Este proyecto fue desarrollado con la asistencia de:
- Claude Code - Asistente de desarrollo impulsado por IA
- Cursor
- OpenAI Codex Cli - Generación y optimización de código