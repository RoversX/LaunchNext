# LaunchNext

**Sprachen**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 Download

**[Hier herunterladen](https://github.com/RoversX/LaunchNext/releases/latest)** - Holen Sie sich die neueste Version

🌐 **Website**: [closex.org/launchnext](https://closex.org/launchnext/)  
📚 **Dokumentation**: [docs.closex.org/launchnext](https://docs.closex.org/launchnext/)

⭐ Bitte geben Sie [LaunchNext](https://github.com/RoversX/LaunchNext) und besonders dem ursprünglichen Projekt [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) einen Stern!

| | |
|:---:|:---:|
| ![](../public/banner.webp) | ![](../public/setting1.webp) |
| ![](../public/setting2.webp) | ![](../public/setting3.webp) |

macOS Tahoe hat das Launchpad entfernt, und es ist so schwer zu bedienen, es nutzt nicht Ihre Bio-GPU. Bitte Apple, gebt den Leuten wenigstens eine Option, zurückzuwechseln. Bis dahin ist hier LaunchNext.

*Aufbauend auf [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) von ggkevinnnn — ein riesiges Dankeschön an das Originalprojekt!❤️*

*LaunchNow hat die GPL 3 Lizenz gewählt. LaunchNext folgt denselben Lizenzbedingungen.*

⚠️ **Wenn macOS die App blockiert, führen Sie dies im Terminal aus:**
```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNext.app
```
**Warum**: Ich kann mir Apples Entwicklerzertifikat nicht leisten ($99/Jahr), daher blockiert macOS unsignierte Apps. Dieser Befehl entfernt das Quarantäne-Flag, damit die App ausgeführt werden kann. **Verwenden Sie diesen Befehl nur bei vertrauenswürdigen Apps.**

## Was LaunchNext bietet

- ✅ **Ein-Klick-Import vom alten System-Launchpad** - liest direkt die native Launchpad-SQLite-Datenbank, um Ordner, App-Positionen und Layout wiederherzustellen
- ✅ **Manuelle App-Organisation** - Apps verschieben, Ordner erstellen und das gewünschte Layout behalten
- ✅ **Zwei Rendering-Pfade** - `Legacy Engine` für Kompatibilität und `Next Engine + Core Animation` für das beste Erlebnis
- ✅ **Kompakt- und Vollbildmodus** - mit Unterstützung für getrennte Einstellungen
- ✅ **Tastaturorientierter Workflow** - schnelle Suche, Navigation und Starten
- ✅ **CLI / TUI-Unterstützung** - Layouts direkt im Terminal prüfen und verwalten
- ✅ **Aktivierung per Hot Corner und nativen Gesten** - mehrere globale Möglichkeiten zum Öffnen von LaunchNext
- ✅ **Apps direkt ins Dock ziehen** - verfügbar mit der Core-Animation-Engine
- ✅ **Update-Center mit Markdown-Release-Notes** - reichhaltigere In-App-Update-Erfahrung
- ✅ **Backup- und Wiederherstellungswerkzeuge** - sicherere Exporte und Wiederherstellung
- ✅ **Barrierefreiheit und Controller-Unterstützung** - Sprachfeedback und Controller-Navigation verbessert
- ✅ **Mehrsprachige Unterstützung** - breite Lokalisierungsabdeckung

## Was macOS Tahoe entfernt hat

- ❌ Keine benutzerdefinierte App-Organisation
- ❌ Keine benutzerdefinierten Ordner
- ❌ Keine Drag-and-Drop-Anpassung
- ❌ Keine visuelle App-Verwaltung
- ❌ Erzwungene kategorische Gruppierung

## Datenspeicherung

Anwendungsdaten werden hier gespeichert:

```text
~/Library/Application Support/LaunchNext/Data.store
```

## Native Launchpad-Integration

LaunchNext kann die System-Launchpad-Datenbank direkt lesen:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Installation

### Anforderungen

- macOS 26 (Tahoe) oder neuer
- Apple Silicon oder Intel Prozessor
- Xcode 26 (zum Bauen aus dem Quellcode)

### Aus dem Quellcode bauen

1. **Repository klonen**
   ```bash
   git clone https://github.com/RoversX/LaunchNext.git
   cd LaunchNext
   ```

2. **In Xcode öffnen**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **Bauen und ausführen**
   - Zielgerät auswählen
   - `⌘+R` drücken, um zu bauen und auszuführen
   - Oder `⌘+B` nur zum Bauen

### Kommandozeilen-Build

**Normaler Build:**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**Universelles Binary (Intel + Apple Silicon):**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Verwendung

### Erste Schritte

1. LaunchNext scannt beim ersten Start alle installierten Apps
2. Importieren Sie Ihr altes Launchpad-Layout oder starten Sie mit einem leeren Layout
3. Nutzen Sie Suche, Tastatur, Drag-and-Drop und Ordner, um Apps zu organisieren
4. Öffnen Sie die Einstellungen, um Engine, Layoutmodus, Aktivierungsmethoden und Automatisierung zu konfigurieren

### Ihr Launchpad importieren

1. Einstellungen öffnen
2. Auf **Import Launchpad** klicken
3. Ihr bestehendes Layout und Ihre Ordner werden automatisch importiert

### Engines und Layoutmodi

- **Legacy Engine** - behält den alten Rendering-Pfad für maximale Kompatibilität bei
- **Next Engine + Core Animation** - empfohlen für das beste Gesamterlebnis und neuere Funktionen
- **Kompakt / Vollbild** - LaunchNext unterstützt beide Modi und kann getrennte Einstellungen speichern

## Wichtige Funktionen

### Aktivierung und Eingabe

- **Hot-Corner-Unterstützung** - LaunchNext aus einer konfigurierbaren Bildschirmecke öffnen
- **Experimentelle native Gestenunterstützung** - Vier-Finger-Pinch- / Tap-Aktionen
- **Globale Tastenkürzel** - LaunchNext von überall öffnen
- **Dock-Drag** - Apps mit der Core-Animation-Engine direkt an das macOS-Dock übergeben

### Automatisierung und Power-User-Workflow

- **CLI / TUI-Unterstützung** - Layouts prüfen, Apps suchen, Ordner erstellen, Apps verschieben und Workflows automatisieren
- **Agent-freundliche Workflows** - gut geeignet für terminalbasierte KI-Agenten und Shell-Automatisierung
- **Kommandozeile aus den Einstellungen aktivieren** - den verwalteten `launchnext`-Befehl installieren oder entfernen

### Update-Erlebnis

- **In-App-Update-Center** - Updates prüfen, ohne die App zu verlassen
- **Markdown-Release-Notes** - reichhaltigere Anzeige direkt in den Einstellungen
- **Moderne Benachrichtigungs-API** - aktualisierte Zustellung für neuere macOS-Versionen

### Backup und Wiederherstellung

- Backups in den Einstellungen erstellen und wiederherstellen
- Zuverlässigeres Backup-Exportverhalten
- Sichererer Umgang mit temporären Dateien und Aufräumvorgängen

### Barrierefreiheit und Navigation

- **Sprachunterstützung** - Apps und Ordner werden während der Navigation angesagt
- **Controller-Unterstützung** - LaunchNext und Ordner mit einem Gamecontroller steuern
- **Tastaturorientierte Interaktion** - schnelle Suche und Navigation ohne Maus

## Leistung und Stabilität

- Intelligentes Icon-Caching für flüssiges Browsen
- Lazy Loading und Hintergrund-Scanning für große Bibliotheken
- Bessere Statussynchronisierung zwischen Einstellungen und Navigation
- Verbesserte Zuverlässigkeit bei Updates, Backup-Exporten und Gestenwiederherstellung

## Fehlerbehebung

### Häufige Probleme

**Q: Die App startet nicht?**  
A: Stellen Sie sicher, dass Sie macOS 26 oder neuer verwenden, entfernen Sie bei Bedarf die Quarantäne und verwenden Sie nur einen vertrauenswürdigen Build.

**Q: Welche Engine sollte ich verwenden?**  
A: `Next Engine + Core Animation` wird für das beste Erlebnis empfohlen. Verwenden Sie `Legacy Engine` nur, wenn Sie den älteren Kompatibilitätspfad wirklich brauchen.

**Q: Warum existiert der CLI-Befehl noch nicht?**  
A: Aktivieren Sie zuerst die Kommandozeilenschnittstelle in den Einstellungen. LaunchNext kann den verwalteten `launchnext`-Shim für Sie installieren und entfernen.

## Mitwirken

Beiträge sind willkommen.

1. Repository forken
2. Feature-Branch erstellen (`git checkout -b feature/amazing-feature`)
3. Änderungen committen (`git commit -m 'Add amazing feature'`)
4. Branch pushen (`git push origin feature/amazing-feature`)
5. Pull Request öffnen

### Entwicklungsrichtlinien

- Swift-Stilkonventionen befolgen
- Sinnvolle Kommentare für komplexe Logik hinzufügen
- Nach Möglichkeit auf mehreren macOS-Versionen testen
- Experimentelle Funktionen nicht über unzusammenhängende Dateien verteilen
- Entfernbare Integrationen nach Möglichkeit isolieren

## Die Zukunft der App-Verwaltung

Während Apple sich von anpassbaren App-Launchern entfernt, versucht LaunchNext, manuelle Organisation, Benutzerkontrolle und schnellen Zugriff auf modernem macOS zu erhalten.

**LaunchNext** ist nicht nur ein Ersatz für Launchpad — es ist eine praktische Antwort auf eine Workflow-Regression.

---

**LaunchNext** - Holen Sie sich die Kontrolle über Ihren App-Launcher zurück 🚀

*Für macOS-Nutzer, die bei der Anpassbarkeit keine Kompromisse eingehen wollen.*

## Entwicklungstools

- Claude Code
- Cursor
- OpenAI Codex CLI
- Perplexity
- Google

- Die experimentelle Gestenunterstützung basiert auf [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) und dem Fork von [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).❤️

![GitHub downloads](https://img.shields.io/github/downloads/RoversX/LaunchNext/total)
