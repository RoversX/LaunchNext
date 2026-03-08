# LaunchNext

**Lingue**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 Download

**[Scarica qui](https://github.com/RoversX/LaunchNext/releases/latest)** - Ottieni l'ultima versione

⭐ Considera di mettere una stella a [LaunchNext](https://github.com/RoversX/LaunchNext) e soprattutto a [LaunchNow](https://github.com/ggkevinnnn/LaunchNow)!

| | |
|:---:|:---:|
| ![](../public/banner.webp) | ![](../public/setting1.webp) |
| ![](../public/setting2.webp) | ![](../public/setting3.webp) |

macOS Tahoe ha rimosso il launchpad, ed è così difficile da usare, non utilizza la tua Bio GPU, per favore Apple, almeno dà alle persone un'opzione per tornare indietro. Prima di allora, ecco LaunchNext

*Basato su [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) di ggkevinnnn — un enorme grazie al progetto originale!❤️*

*LaunchNow ha scelto la licenza GPL 3. LaunchNext segue gli stessi termini di licenza.*

⚠️ **Se macOS blocca l'app, esegui questo nel Terminale:**
```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNext.app
```
**Perché**: Non posso permettermi il certificato sviluppatore di Apple ($99/anno), quindi macOS blocca le app non firmate. Questo comando rimuove il flag di quarantena per permetterne l'esecuzione. **Usa questo comando solo su app di cui ti fidi.**

### Cosa Offre LaunchNext
- ✅ **Importazione con un clic dal vecchio Launchpad di sistema** - legge direttamente il tuo database SQLite nativo del Launchpad (`/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db`) per ricreare perfettamente le tue cartelle esistenti, posizioni delle app e layout
- ✅ **Esperienza Launchpad classica** - funziona esattamente come l'amata interfaccia originale
- ✅ **Supporto multi-lingua** - completa internazionalizzazione con inglese, cinese, giapponese, francese, spagnolo, tedesco e russo
- ✅ **Nascondi etichette icone** - vista pulita e minimalista quando non hai bisogno dei nomi delle app
- ✅ **Dimensioni icone personalizzate** - regola le dimensioni delle icone secondo le tue preferenze
- ✅ **Gestione intelligente delle cartelle** - crea e organizza cartelle proprio come prima
- ✅ **Ricerca istantanea e navigazione da tastiera** - trova le app velocemente

### Cosa Abbiamo Perso in macOS Tahoe
- ❌ Nessuna organizzazione personalizzata delle app
- ❌ Nessuna cartella creata dall'utente
- ❌ Nessuna personalizzazione drag-and-drop
- ❌ Nessuna gestione visuale delle app
- ❌ Raggruppamento categorico forzato


### Archiviazione Dati
I dati dell'applicazione sono memorizzati in modo sicuro in:
```
~/Library/Application Support/LaunchNext/Data.store
```

### Integrazione Launchpad Nativa
Legge direttamente dal database Launchpad di sistema:
```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Installazione

### Requisiti
- macOS 26 (Tahoe) o successivo
- Processore Apple Silicon o Intel
- Xcode 26 (per compilare dal codice sorgente)

### Compila dal Codice Sorgente

1. **Clona il repository**
   ```bash
   git clone https://github.com/yourusername/LaunchNext.git
   cd LaunchNext
   ```

2. **Apri in Xcode**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **Compila ed esegui**
   - Seleziona il tuo dispositivo target
   - Premi `⌘+R` per compilare ed eseguire
   - O `⌘+B` per solo compilare

### Compilazione da Riga di Comando

**Compilazione Normale:**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**Compilazione Binaria Universale (Intel + Apple Silicon):**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Utilizzo

### Iniziare
1. **Primo Avvio**: LaunchNext scansiona automaticamente tutte le applicazioni installate
2. **Seleziona**: Clicca per selezionare le app, doppio-clic per avviarle
3. **Cerca**: Digita per filtrare istantaneamente le applicazioni
4. **Organizza**: Trascina le app per creare cartelle e layout personalizzati

### Importa il Tuo Launchpad
1. Apri Impostazioni (icona ingranaggio)
2. Clicca **"Importa Launchpad"**
3. Il tuo layout esistente e le cartelle vengono importati automaticamente


### Modalità di Visualizzazione
- **Finestra**: Finestra flottante con angoli arrotondati
- **Schermo intero**: Modalità a schermo intero per la massima visibilità
- Cambia modalità nelle Impostazioni

## Funzionalità Avanzate

### Interazione Intelligente in Background
- Rilevamento intelligente dei clic previene la chiusura accidentale
- Gestione dei gesti consapevole del contesto
- Protezione del campo di ricerca

### Ottimizzazione delle Prestazioni
- **Cache delle Icone**: Cache intelligente delle immagini per scorrimento fluido
- **Caricamento Lazy**: Uso efficiente della memoria
- **Scansione in Background**: Scoperta delle app non bloccante

### Supporto Multi-Display
- Rilevamento automatico dello schermo
- Posizionamento per display
- Flussi di lavoro multi-monitor senza soluzione di continuità

## Risoluzione dei Problemi

### Problemi Comuni

**D: L'app non si avvia?**
R: Assicurati di avere macOS 26.0+ e controlla i permessi di sistema.

## Contribuire

Accogliamo i contributi! Per favore:

1. Fai un fork del repository
2. Crea un branch per la funzionalità (`git checkout -b feature/amazing-feature`)
3. Committa le modifiche (`git commit -m 'Add amazing feature'`)
4. Pusha al branch (`git push origin feature/amazing-feature`)
5. Apri una Pull Request

### Linee Guida per lo Sviluppo
- Segui le convenzioni di stile Swift
- Aggiungi commenti significativi per la logica complessa
- Testa su multiple versioni di macOS
- Mantieni la compatibilità all'indietro

## Il Futuro della Gestione delle App

Mentre Apple si allontana dalle interfacce personalizzabili, LaunchNext rappresenta l'impegno della community per il controllo dell'utente e la personalizzazione. Spero che Apple riporti il launchpad.

**LaunchNext** non è solo un sostituto del Launchpad—è una dichiarazione che la scelta dell'utente conta.


---

**LaunchNext** - Riprendi il Controllo del Tuo Launcher 🚀

*Costruito per gli utenti macOS che rifiutano di compromettere sulla personalizzazione.*
