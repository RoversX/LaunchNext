# LaunchNext

**Jazyky**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 Stáhnout

**[Stáhnout zde](https://github.com/RoversX/LaunchNext/releases/latest)** - Získejte nejnovější verzi

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

### Co LaunchNext přináší
- ✅ **Import jedním kliknutím ze starého systémového Launchpadu** - přímo čte vaši nativní Launchpad SQLite databázi (`/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db`) pro perfektní obnovení vašich existujících složek, pozic aplikací a rozložení
- ✅ **Klasický Launchpad zážitek** - funguje přesně jako milované původní rozhraní
- ✅ **Vícejazyčná podpora** - plná internacionalizace s angličtinou, čínštinou, japonštinou, francouzštinou, španělštinou, němčinou a ruštinou
- ✅ **Skrýt popisky ikon** - čistý, minimalistický pohled, když nepotřebujete názvy aplikací
- ✅ **Vlastní velikosti ikon** - upravte rozměry ikon podle vašich preferencí
- ✅ **Inteligentní správa složek** - vytvářejte a organizujte složky stejně jako dříve
- ✅ **Okamžité vyhledávání a navigace klávesnicí** - rychle najděte aplikace

### Co jsme ztratili v macOS Tahoe
- ❌ Žádná vlastní organizace aplikací
- ❌ Žádné uživatelem vytvořené složky
- ❌ Žádné přizpůsobení přetažením
- ❌ Žádná vizuální správa aplikací
- ❌ Vynucené kategoriální seskupení


### Ukládání dat
Data aplikace jsou bezpečně uložena v:
```
~/Library/Application Support/LaunchNext/Data.store
```

### Nativní integrace Launchpadu
Čte přímo ze systémové databáze Launchpadu:
```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Instalace

### Požadavky
- macOS 15 (Sequoia) nebo novější
- Procesor Apple Silicon nebo Intel
- Xcode 26 (pro sestavení ze zdrojového kódu)

### Sestavení ze zdrojového kódu

1. **Klonovat repozitář**
   ```bash
   git clone https://github.com/yourusername/LaunchNext.git
   cd LaunchNext
   ```

2. **Sestavit aktualizátor**
   ```bash
   swift build --package-path UpdaterScripts/SwiftUpdater --configuration release --arch arm64 --arch x86_64 --product SwiftUpdater
   ```

3. **Otevřít v Xcode**
   ```bash
   open LaunchNext.xcodeproj
   ```

4. **Sestavit a spustit**
   - Vyberte vaše cílové zařízení
   - Stiskněte `⌘+R` pro sestavení a spuštění
   - Nebo `⌘+B` pouze pro sestavení

### Sestavení z příkazové řádky

**Běžné sestavení:**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**Univerzální binární sestavení (Intel + Apple Silicon):**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Použití

### Začínáme
1. **První spuštění**: LaunchNext automaticky skenuje všechny nainstalované aplikace
2. **Výběr**: Klikněte pro výběr aplikací, dvojklik pro spuštění
3. **Vyhledávání**: Píšte pro okamžité filtrování aplikací
4. **Organizace**: Přetažením aplikací vytvářejte složky a vlastní rozložení

### Import vašeho Launchpadu
1. Otevřete Nastavení (ikona ozubeného kola)
2. Klikněte **"Import Launchpad"**
3. Vaše existující rozložení a složky se automaticky importují


### Režimy zobrazení
- **Okno**: Plovoucí okno se zaoblenými rohy
- **Celá obrazovka**: Režim celé obrazovky pro maximální viditelnost
- Přepínání režimů v Nastavení

## Pokročilé funkce

### Inteligentní interakce na pozadí
- Inteligentní detekce kliknutí zabraňuje náhodnému zavření
- Kontextově orientovaná správa gest
- Ochrana vyhledávacího pole

### Optimalizace výkonu
- **Ukládání ikon do mezipaměti**: Inteligentní ukládání obrázků do mezipaměti pro plynulé posouvání
- **Líné načítání**: Efektivní využití paměti
- **Skenování na pozadí**: Neblokující objevování aplikací

### Podpora více displejů
- Automatická detekce obrazovky
- Umístění podle displeje
- Bezproblémové pracovní postupy na více monitorech

## Řešení problémů

### Běžné problémy

**Q: Aplikace se nespustí?**
A: Ujistěte se, že máte macOS 15.0+ a zkontrolujte systémová oprávnění.

## Přispívání

Vítáme příspěvky! Prosím:

1. Forkněte repozitář
2. Vytvořte větev funkcí (`git checkout -b feature/amazing-feature`)
3. Commitněte změny (`git commit -m 'Add amazing feature'`)
4. Pushněte do větve (`git push origin feature/amazing-feature`)
5. Otevřete Pull Request

### Pokyny pro vývoj
- Dodržujte konvence stylu Swift
- Přidejte smysluplné komentáře pro složitou logiku
- Testujte na více verzích macOS
- Udržujte zpětnou kompatibilitu

## Budoucnost správy aplikací

Jak se Apple vzdaluje od přizpůsobitelných rozhraní, LaunchNext představuje závazek komunity k uživatelskému ovládání a personalizaci. Doufám, že Apple přinese launchpad zpět.

**LaunchNext** není jen náhrada Launchpadu—je to prohlášení, že volba uživatele záleží.


---

**LaunchNext** - Získejte zpět kontrolu nad vaším spouštěčem aplikací 🚀

*Vytvořeno pro uživatele macOS, kteří odmítají kompromisy v přizpůsobení.*
