# LaunchNext

**Lingue**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 Download

**[Scarica qui](https://github.com/RoversX/LaunchNext/releases/latest)** - Ottieni l'ultima versione

🌐 **Sito web**: [closex.org/launchnext](https://closex.org/launchnext/)  
📚 **Documentazione**: [docs.closex.org/launchnext](https://docs.closex.org/launchnext/)

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
**Perché**: non posso permettermi il certificato sviluppatore Apple ($99/anno), quindi macOS blocca le app non firmate. Questo comando rimuove il flag di quarantena per consentirne l'esecuzione. **Usa questo comando solo con app di cui ti fidi.**

## Cosa offre LaunchNext

- ✅ **Importazione con un clic dal vecchio Launchpad di sistema** - legge direttamente il database SQLite nativo di Launchpad per ricreare cartelle, posizioni delle app e layout
- ✅ **Organizzazione manuale delle app** - sposta le app, crea cartelle e mantieni il layout come preferisci
- ✅ **Due percorsi di rendering** - `Legacy Engine` per la compatibilità e `Next Engine + Core Animation` per la migliore esperienza
- ✅ **Modalità compatta e a schermo intero** - con supporto a impostazioni separate
- ✅ **Workflow orientato alla tastiera** - ricerca, navigazione e apertura rapide
- ✅ **Supporto CLI / TUI** - ispeziona e gestisci il layout dal terminale
- ✅ **Attivazione con Hot Corner e gesti nativi** - più modi per aprire LaunchNext globalmente
- ✅ **Trascina le app direttamente nel Dock** - disponibile con il motore Core Animation
- ✅ **Centro aggiornamenti con note di rilascio Markdown** - esperienza di aggiornamento integrata più ricca
- ✅ **Strumenti di backup e ripristino** - esportazione e recupero più sicuri
- ✅ **Accessibilità e supporto controller** - feedback vocale e navigazione controller migliorati
- ✅ **Supporto multilingua** - ampia copertura di localizzazione

## Cosa macOS Tahoe ha tolto

- ❌ Nessuna organizzazione personalizzata delle app
- ❌ Nessuna cartella creata dall'utente
- ❌ Nessuna personalizzazione drag-and-drop
- ❌ Nessuna gestione visiva delle app
- ❌ Raggruppamento categorico forzato

## Archiviazione dati

I dati dell'applicazione sono archiviati in:

```text
~/Library/Application Support/LaunchNext/Data.store
```

## Integrazione nativa con Launchpad

LaunchNext può leggere direttamente il database Launchpad del sistema:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Installazione

### Requisiti

- macOS 26 (Tahoe) o successivo
- Processore Apple Silicon o Intel
- Xcode 26 (per compilare dal sorgente)

### Compila dal codice sorgente

1. **Clona il repository**
   ```bash
   git clone https://github.com/RoversX/LaunchNext.git
   cd LaunchNext
   ```

2. **Apri in Xcode**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **Compila ed esegui**
   - Seleziona il dispositivo target
   - Premi `⌘+R` per compilare ed eseguire
   - Oppure `⌘+B` per compilare soltanto

### Compilazione da riga di comando

**Build standard:**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**Build universale (Intel + Apple Silicon):**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Utilizzo

### Iniziare

1. LaunchNext analizza le app installate al primo avvio
2. Importa il vecchio layout Launchpad o parti da un layout vuoto
3. Usa ricerca, tastiera, drag-and-drop e cartelle per organizzare le app
4. Apri Impostazioni per configurare motore, modalità di layout, metodi di attivazione e automazione

### Importa il tuo Launchpad

1. Apri Impostazioni
2. Fai clic su **Import Launchpad**
3. Il layout e le cartelle esistenti vengono importati automaticamente

### Motori e modalità di layout

- **Legacy Engine** - mantiene il vecchio percorso di rendering per privilegiare la compatibilità
- **Next Engine + Core Animation** - consigliato per la migliore esperienza complessiva e le funzionalità più recenti
- **Compatta / Schermo intero** - LaunchNext supporta entrambe le modalità e può mantenere impostazioni separate

## Funzionalità chiave

### Attivazione e input

- **Supporto Hot Corner** - apri LaunchNext da un angolo dello schermo configurabile
- **Supporto sperimentale ai gesti nativi** - azioni pinch / tap a quattro dita
- **Supporto alle scorciatoie globali** - apri LaunchNext da qualsiasi punto
- **Trascinamento nel Dock** - consegna le app direttamente al Dock di macOS con il motore Core Animation

### Automazione e workflow avanzato

- **Supporto CLI / TUI** - ispeziona layout, cerca app, crea cartelle, sposta app e automatizza workflow
- **Workflow adatti agli agent** - funziona bene con agent AI basati su terminale e shell automation
- **Abilitazione della riga di comando dalle Impostazioni** - installa o rimuovi il comando gestito `launchnext`

### Esperienza di aggiornamento

- **Centro aggiornamenti integrato** - controlla gli aggiornamenti senza uscire dall'app
- **Note di rilascio Markdown** - visualizzazione più ricca direttamente nelle Impostazioni
- **API di notifica moderna** - consegna delle notifiche aggiornata per le versioni recenti di macOS

### Backup e ripristino

- Crea e ripristina backup dalle Impostazioni
- Comportamento di esportazione backup più affidabile
- Gestione più sicura di file temporanei e pulizia

### Accessibilità e navigazione

- **Supporto al feedback vocale** - annuncia app e cartelle durante la navigazione
- **Supporto controller** - naviga LaunchNext e le cartelle con un game controller
- **Interazione orientata alla tastiera** - ricerca e navigazione rapide senza dipendere dal mouse

## Prestazioni e stabilità

- Cache intelligente delle icone per una navigazione fluida
- Caricamento lazy e scansione in background per librerie grandi
- Migliore sincronizzazione dello stato tra Impostazioni e navigazione
- Affidabilità migliorata per aggiornamenti, esportazione backup e recupero dei gesti

## Risoluzione dei problemi

### Problemi comuni

**Q: L'app non si avvia?**  
A: Verifica di essere su macOS 26 o successivo, rimuovi la quarantena se necessario e assicurati di usare una build affidabile.

**Q: Quale motore dovrei usare?**  
A: `Next Engine + Core Animation` è quello consigliato per la migliore esperienza. Usa `Legacy Engine` solo se ti serve davvero il vecchio percorso di compatibilità.

**Q: Perché il comando CLI non esiste ancora?**  
A: Abilita prima l'interfaccia a riga di comando nelle Impostazioni. LaunchNext può installare e rimuovere per te lo shim gestito `launchnext`.

## Contribuire

I contributi sono benvenuti.

1. Fai fork del repository
2. Crea un branch funzionale (`git checkout -b feature/amazing-feature`)
3. Esegui il commit delle modifiche (`git commit -m 'Add amazing feature'`)
4. Esegui il push del branch (`git push origin feature/amazing-feature`)
5. Apri una Pull Request

### Linee guida per lo sviluppo

- Segui le convenzioni di stile Swift
- Aggiungi commenti significativi per la logica complessa
- Testa su più versioni di macOS quando possibile
- Evita di spargere funzionalità sperimentali in file non correlati
- Mantieni isolate le integrazioni removibili quando possibile

## Il futuro della gestione delle app

Mentre Apple si allontana dai launcher personalizzabili, LaunchNext cerca di mantenere organizzazione manuale, controllo utente e accesso rapido su macOS moderno.

**LaunchNext** non è solo un sostituto di Launchpad — è una risposta pratica a una regressione del workflow.

---

**LaunchNext** - Riprendi il controllo del tuo launcher di app 🚀

*Per utenti macOS che non vogliono scendere a compromessi sulla personalizzazione.*

## Strumenti di sviluppo

- Claude Code
- Cursor
- OpenAI Codex CLI
- Perplexity
- Google

- Il supporto sperimentale ai gesti è costruito su [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) e sul fork di [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).❤️

![GitHub downloads](https://img.shields.io/github/downloads/RoversX/LaunchNext/total)
