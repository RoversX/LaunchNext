# LaunchNext

**Jazyky**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 Stáhnout

**[Stáhnout zde](https://github.com/RoversX/LaunchNext/releases/latest)** - Získejte nejnovější verzi

🌐 **Web**: [closex.org/launchnext](https://closex.org/launchnext/)  
📚 **Dokumentace**: [docs.closex.org/launchnext](https://docs.closex.org/launchnext/)

⭐ Zvažte označení hvězdičkou [LaunchNext](https://github.com/RoversX/LaunchNext) a zejména [LaunchNow](https://github.com/ggkevinnnn/LaunchNow)!

| | |
|:---:|:---:|
| ![](../public/banner.webp) | ![](../public/setting1.webp) |
| ![](../public/setting2.webp) | ![](../public/setting3.webp) |

macOS Tahoe odstranil launchpad a je tak těžký k použití, nevyužívá vaše Bio GPU, prosím Apple, alespoň dejte lidem možnost přepnout zpět. Než k tomu dojde, zde je LaunchNext

*Postaveno na [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) od ggkevinnnn — obrovské díky původnímu projektu!❤️*

*LaunchNow si vybral licenci GPL 3. LaunchNext následuje stejné licenční podmínky.*

⚠️ **Pokud macOS zablokuje aplikaci, spusťte toto v Terminálu:**
```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNext.app
```
**Proč**: Nemohu si dovolit Apple vývojářský certifikát ($99/rok), takže macOS blokuje nepodepsané aplikace. Tento příkaz odstraní karanténní příznak a umožní spuštění. **Používejte tento příkaz pouze u aplikací, kterým důvěřujete.**

## Co LaunchNext přináší

- ✅ **Import jedním kliknutím ze starého systémového Launchpadu** - přímo čte nativní SQLite databázi Launchpadu a obnovuje složky, pozice aplikací a rozložení
- ✅ **Ruční organizace aplikací** - přesouvejte aplikace, vytvářejte složky a udržujte rozložení podle sebe
- ✅ **Dvě renderovací cesty** - `Legacy Engine` pro kompatibilitu a `Next Engine + Core Animation` pro nejlepší zážitek
- ✅ **Kompaktní a celoobrazovkový režim** - s podporou oddělených nastavení
- ✅ **Pracovní postup zaměřený na klávesnici** - rychlé vyhledávání, navigace a spouštění
- ✅ **Podpora CLI / TUI** - kontrolujte a spravujte rozložení z terminálu
- ✅ **Aktivace přes Hot Corner a nativní gesta** - více způsobů, jak LaunchNext globálně otevřít
- ✅ **Přetahování aplikací přímo do Docku** - dostupné s renderovacím motorem Core Animation
- ✅ **Centrum aktualizací s Markdown poznámkami k vydání** - bohatší aktualizace přímo v aplikaci
- ✅ **Nástroje pro zálohu a obnovení** - bezpečnější export a návrat dat
- ✅ **Přístupnost a podpora ovladače** - vylepšená hlasová odezva i navigace ovladačem
- ✅ **Vícejazyčná podpora** - široké pokrytí lokalizací

## Co macOS Tahoe vzal

- ❌ Žádná vlastní organizace aplikací
- ❌ Žádné uživatelem vytvořené složky
- ❌ Žádné přizpůsobení přetažením
- ❌ Žádná vizuální správa aplikací
- ❌ Vynucené kategoriální seskupení

## Ukládání dat

Data aplikace jsou uložená zde:

```text
~/Library/Application Support/LaunchNext/Data.store
```

## Nativní integrace Launchpadu

LaunchNext může číst přímo ze systémové databáze Launchpadu:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Instalace

### Požadavky

- macOS 26 (Tahoe) nebo novější
- Procesor Apple Silicon nebo Intel
- Xcode 26 (pro sestavení ze zdrojového kódu)

### Sestavení ze zdrojového kódu

1. **Klonovat repozitář**
   ```bash
   git clone https://github.com/RoversX/LaunchNext.git
   cd LaunchNext
   ```

2. **Otevřít v Xcode**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **Sestavit a spustit**
   - Vyberte cílové zařízení
   - Stiskněte `⌘+R` pro sestavení a spuštění
   - Nebo `⌘+B` pouze pro sestavení

### Sestavení z příkazové řádky

**Běžné sestavení:**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**Univerzální binárka (Intel + Apple Silicon):**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Použití

### Začínáme

1. LaunchNext při prvním spuštění naskenuje všechny nainstalované aplikace
2. Importujte staré rozložení Launchpadu nebo začněte s prázdným rozložením
3. Používejte vyhledávání, klávesnici, drag-and-drop a složky pro organizaci aplikací
4. Otevřete Nastavení pro konfiguraci enginu, režimu rozložení, aktivace a automatizace

### Import vašeho Launchpadu

1. Otevřete Nastavení
2. Klikněte na **Import Launchpad**
3. Vaše existující rozložení a složky se automaticky importují

### Enginy a režimy rozložení

- **Legacy Engine** - zachovává starou renderovací cestu pro maximální kompatibilitu
- **Next Engine + Core Animation** - doporučeno pro nejlepší celkový zážitek a novější funkce
- **Kompaktní / Celá obrazovka** - LaunchNext podporuje oba režimy a může uchovávat oddělená nastavení

## Klíčové funkce

### Aktivace a vstup

- **Podpora Hot Corner** - otevřete LaunchNext z konfigurovatelného rohu obrazovky
- **Experimentální podpora nativních gest** - čtyřprsté pinch / tap akce
- **Podpora globálních zkratek** - otevřete LaunchNext odkudkoli
- **Přetažení do Docku** - předávejte aplikace přímo do macOS Docku s Core Animation enginem

### Automatizace a pokročilý workflow

- **Podpora CLI / TUI** - kontrolujte rozložení, vyhledávejte aplikace, vytvářejte složky, přesouvejte aplikace a automatizujte workflow
- **Workflow vhodný pro agenty** - funguje dobře s AI agenty v terminálu a shell automatizací
- **Povolení příkazové řádky z Nastavení** - můžete nainstalovat nebo odstranit spravovaný příkaz `launchnext`

### Aktualizace

- **Centrum aktualizací v aplikaci** - kontrolujte aktualizace bez opuštění aplikace
- **Markdown poznámky k vydání** - bohatší zobrazení přímo v Nastavení
- **Moderní API oznámení** - aktualizované doručování oznámení pro novější verze macOS

### Záloha a obnovení

- Vytvářejte a obnovujte zálohy z Nastavení
- Spolehlivější export záloh
- Bezpečnější práce s dočasnými soubory a úklidem

### Přístupnost a navigace

- **Hlasová odezva** - během navigace oznamuje aplikace a složky
- **Podpora ovladače** - ovládejte LaunchNext a složky gamepadem
- **Interakce zaměřená na klávesnici** - rychlé vyhledávání a navigace bez myši

## Výkon a stabilita

- Inteligentní cache ikon pro plynulé procházení
- Líné načítání a skenování na pozadí pro velké knihovny
- Lepší synchronizace stavu mezi Nastavením a navigací
- Vyšší spolehlivost aktualizací, exportu záloh a obnovy gest

## Řešení problémů

### Běžné problémy

**Q: Aplikace se nespustí?**  
A: Ujistěte se, že používáte macOS 26 nebo novější, případně odstraňte quarantine a používejte pouze důvěryhodný build.

**Q: Který engine mám použít?**  
A: `Next Engine + Core Animation` je doporučený pro nejlepší zážitek. `Legacy Engine` používejte jen tehdy, pokud opravdu potřebujete starou cestu kompatibility.

**Q: Proč příkaz CLI ještě neexistuje?**  
A: Nejdřív povolte rozhraní příkazové řádky v Nastavení. LaunchNext za vás může nainstalovat i odstranit spravovaný shim `launchnext`.

## Přispívání

Příspěvky jsou vítány.

1. Forkněte repozitář
2. Vytvořte feature branch (`git checkout -b feature/amazing-feature`)
3. Commitněte změny (`git commit -m 'Add amazing feature'`)
4. Pushněte branch (`git push origin feature/amazing-feature`)
5. Otevřete Pull Request

### Pokyny pro vývoj

- Dodržujte konvence stylu Swift
- Přidávejte smysluplné komentáře ke složité logice
- Pokud možno testujte na více verzích macOS
- Nerozmisťujte experimentální funkce do nesouvisejících souborů
- Odnímatelné integrace držte pokud možno odděleně

## Budoucnost správy aplikací

Jak se Apple vzdaluje od přizpůsobitelných launcherů aplikací, LaunchNext se snaží zachovat ruční organizaci, uživatelskou kontrolu a rychlý přístup i na moderním macOS.

**LaunchNext** není jen náhrada Launchpadu — je to praktická odpověď na regresi workflow.

---

**LaunchNext** - Získejte zpět kontrolu nad svým spouštěčem aplikací 🚀

*Pro uživatele macOS, kteří nechtějí dělat kompromisy v přizpůsobení.*

## Vývojové nástroje

- Claude Code
- Cursor
- OpenAI Codex CLI
- Perplexity
- Google

- Experimentální podpora gest je postavená na [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) a forku od [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).❤️

![GitHub downloads](https://img.shields.io/github/downloads/RoversX/LaunchNext/total)
