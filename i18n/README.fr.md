# LaunchNext

**Langues**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 Télécharger

**[Télécharger ici](https://github.com/RoversX/LaunchNext/releases/latest)** - Obtenez la dernière version

🌐 **Site web**: [closex.org/launchnext](https://closex.org/launchnext/)  
📚 **Documentation**: [docs.closex.org/launchnext](https://docs.closex.org/launchnext/)

⭐ Pensez à donner une étoile à [LaunchNext](https://github.com/RoversX/LaunchNext) et au projet original [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) !

| | |
|:---:|:---:|
| ![](../public/banner.webp) | ![](../public/setting1.webp) |
| ![](../public/setting2.webp) | ![](../public/setting3.webp) |

macOS Tahoe a supprimé le Launchpad, et la nouvelle interface est difficile à utiliser, elle n'utilise pas pleinement votre Bio GPU. Apple, donnez au moins aux utilisateurs une option pour revenir en arrière. En attendant, voici LaunchNext.

*Construit sur [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) par ggkevinnnn — un immense merci au projet original !❤️*

*LaunchNow a choisi la licence GPL 3. LaunchNext suit les mêmes conditions de licence.*

⚠️ **Si macOS bloque l'application, exécutez ceci dans le Terminal :**
```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNext.app
```
**Pourquoi** : je ne peux pas me permettre le certificat développeur Apple (99 $/an), donc macOS peut bloquer les builds non signés. Cette commande supprime le flag de quarantaine pour permettre l'exécution. **Utilisez cette commande uniquement pour des applications de confiance.**

## Ce que LaunchNext apporte

- ✅ **Import en un clic depuis l'ancien Launchpad système** - lit directement la base SQLite native de Launchpad pour recréer dossiers, positions d'apps et disposition
- ✅ **Organisation manuelle des apps** - déplacer des apps, créer des dossiers et conserver votre disposition
- ✅ **Deux moteurs de rendu** - `Legacy Engine` pour la compatibilité et `Next Engine + Core Animation` pour la meilleure expérience
- ✅ **Modes compact et plein écran** - avec prise en charge de réglages séparés
- ✅ **Flux orienté clavier** - recherche, navigation et lancement rapides
- ✅ **Support CLI / TUI** - inspectez et gérez la disposition depuis le terminal
- ✅ **Activation via Hot Corner et gestes natifs** - plusieurs façons d'ouvrir LaunchNext globalement
- ✅ **Glisser des apps directement vers le Dock** - disponible avec le moteur Core Animation
- ✅ **Centre de mise à jour avec release notes Markdown** - expérience de mise à jour intégrée plus riche
- ✅ **Outils de sauvegarde et de restauration** - exports et récupération plus sûrs
- ✅ **Accessibilité et support manette** - retour vocal et navigation manette améliorés
- ✅ **Support multilingue** - large couverture de localisation

## Ce que macOS Tahoe a retiré

- ❌ Pas d'organisation personnalisée des applications
- ❌ Pas de dossiers créés par l'utilisateur
- ❌ Pas de personnalisation par glisser-déposer
- ❌ Pas de gestion visuelle des applications
- ❌ Regroupement catégoriel forcé

## Stockage des données

Les données de l'application sont stockées ici :

```text
~/Library/Application Support/LaunchNext/Data.store
```

## Intégration native avec Launchpad

LaunchNext peut lire directement la base Launchpad du système :

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Installation

### Configuration requise

- macOS 26 (Tahoe) ou version ultérieure
- Processeur Apple Silicon ou Intel
- Xcode 26 (pour compiler depuis les sources)

### Compiler depuis les sources

1. **Cloner le dépôt**
   ```bash
   git clone https://github.com/RoversX/LaunchNext.git
   cd LaunchNext
   ```

2. **Ouvrir dans Xcode**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **Compiler et exécuter**
   - Sélectionnez votre appareil cible
   - Appuyez sur `⌘+R` pour compiler et exécuter
   - Ou `⌘+B` pour compiler seulement

### Compilation en ligne de commande

**Compilation standard :**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**Binaire universel (Intel + Apple Silicon) :**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Utilisation

### Premiers pas

1. LaunchNext analyse les applications installées au premier lancement
2. Importez votre ancien layout Launchpad ou partez d'une disposition vide
3. Utilisez la recherche, le clavier, le glisser-déposer et les dossiers pour organiser vos apps
4. Ouvrez les Réglages pour configurer le moteur, le mode d'affichage, les méthodes d'activation et l'automatisation

### Importer votre Launchpad

1. Ouvrez les Réglages
2. Cliquez sur **Import Launchpad**
3. Vos dossiers et votre disposition existants sont importés automatiquement

### Moteurs et modes d'affichage

- **Legacy Engine** - conserve l'ancien chemin de rendu pour privilégier la compatibilité
- **Next Engine + Core Animation** - recommandé pour la meilleure expérience globale et les fonctionnalités plus récentes
- **Compact / Plein écran** - LaunchNext prend en charge les deux modes et peut conserver des réglages séparés

## Fonctionnalités clés

### Activation et entrée

- **Support Hot Corner** - ouvrir LaunchNext depuis un coin d'écran configurable
- **Support expérimental des gestes natifs** - actions pinch / tap à quatre doigts
- **Support des raccourcis globaux** - ouvrir LaunchNext depuis n'importe où
- **Glisser vers le Dock** - envoyer directement les apps au Dock macOS avec le moteur Core Animation

### Automatisation et workflow avancé

- **Support CLI / TUI** - inspecter les dispositions, rechercher des apps, créer des dossiers, déplacer des apps et automatiser des workflows
- **Workflow adapté aux agents** - fonctionne bien avec les agents IA orientés terminal et l'automatisation shell
- **Activation de la ligne de commande depuis les Réglages** - installer ou retirer la commande gérée `launchnext`

### Expérience de mise à jour

- **Centre de mise à jour intégré** - vérifier les mises à jour sans quitter l'app
- **Release notes Markdown** - affichage plus riche directement dans les Réglages
- **API de notifications moderne** - livraison des notifications mise à jour pour les nouvelles versions de macOS

### Sauvegarde et restauration

- Créez et restaurez des sauvegardes depuis les Réglages
- Export de sauvegarde plus fiable
- Gestion plus sûre des fichiers temporaires et du nettoyage

### Accessibilité et navigation

- **Support du retour vocal** - annonce des apps et dossiers pendant la navigation
- **Support manette** - naviguer dans LaunchNext et dans les dossiers avec une manette
- **Interaction orientée clavier** - recherche et navigation rapides sans dépendre de la souris

## Performances et stabilité

- Mise en cache intelligente des icônes pour une navigation fluide
- Chargement paresseux et scan en arrière-plan pour les grandes bibliothèques
- Meilleure synchronisation d'état entre les réglages et la navigation
- Fiabilité améliorée autour des mises à jour, des exports de sauvegarde et de la récupération des gestes

## Dépannage

### Problèmes courants

**Q : L'application ne démarre pas ?**  
R : Vérifiez que vous êtes bien sur macOS 26 ou plus récent, retirez éventuellement la quarantaine et assurez-vous d'utiliser un build de confiance.

**Q : Quel moteur utiliser ?**  
R : `Next Engine + Core Animation` est recommandé pour la meilleure expérience. Utilisez `Legacy Engine` uniquement si vous avez vraiment besoin de l'ancien chemin de compatibilité.

**Q : Pourquoi la commande CLI n'existe pas encore ?**  
R : Activez d'abord l'interface en ligne de commande dans les Réglages. LaunchNext peut installer et supprimer pour vous le shim `launchnext` géré.

## Contribution

Les contributions sont les bienvenues.

1. Forkez le dépôt
2. Créez une branche de fonctionnalité (`git checkout -b feature/amazing-feature`)
3. Commitez vos changements (`git commit -m 'Add amazing feature'`)
4. Poussez la branche (`git push origin feature/amazing-feature`)
5. Ouvrez une Pull Request

### Directives de développement

- Suivez les conventions de style Swift
- Ajoutez des commentaires utiles pour la logique complexe
- Testez sur plusieurs versions de macOS si possible
- Évitez de disperser les fonctionnalités expérimentales dans des fichiers non liés
- Isolez autant que possible les intégrations amovibles

## L'avenir de la gestion d'applications

Alors qu'Apple s'éloigne des lanceurs d'apps personnalisables, LaunchNext tente de préserver l'organisation manuelle, le contrôle utilisateur et l'accès rapide sur macOS moderne.

**LaunchNext** n'est pas seulement un remplaçant de Launchpad — c'est une réponse pratique à une régression de workflow.

---

**LaunchNext** - Reprenez le contrôle de votre lanceur d'apps 🚀

*Conçu pour les utilisateurs macOS qui refusent de compromettre la personnalisation.*

## Outils de développement

- Claude Code
- Cursor
- OpenAI Codex CLI
- Perplexity
- Google

- Le support expérimental des gestes est construit sur [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) et le fork de [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).❤️

![GitHub downloads](https://img.shields.io/github/downloads/RoversX/LaunchNext/total)
