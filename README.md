# LaunchNext

**Languages**: [English](README.md) | [中文](i18n/README.zh.md) | [日本語](i18n/README.ja.md) | [한국어](i18n/README.ko.md) | [Français](i18n/README.fr.md) | [Español](i18n/README.es.md) | [Deutsch](i18n/README.de.md) | [Русский](i18n/README.ru.md) | [हिन्दी](i18n/README.hi.md) | [Tiếng Việt](i18n/README.vi.md) | [Italiano](i18n/README.it.md) | [Čeština](i18n/README.cs.md)

## 📥 Download

**[Download here](https://github.com/RoversX/LaunchNext/releases/latest)** - Get the latest release

🌐 **Website**: [closex.org/launchnext](https://closex.org/launchnext/)  
📚 **Docs**: [docs.closex.org/launchnext](https://docs.closex.org/launchnext/)

⭐ Consider starring [LaunchNext](https://github.com/RoversX/LaunchNext) and especially [LaunchNow](https://github.com/ggkevinnnn/LaunchNow)!

| | |
|:---:|:---:|
| ![](./public/banner.webp) | ![](./public/setting1.webp) |
| ![](./public/setting2.webp) | ![](./public/setting3.webp) |

MacOS Tahoe removed launchpad,and it's so hard to use, it's doesn't use your Bio GPU, please apple, at least give people an option to switch back. Before that, here is LaunchNext

*Built upon [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) by ggkevinnnn - huge thanks to the original project!❤️*

*LaunchNow has chosen the GPL 3 license. LaunchNext follows the same licensing terms.*

⚠️ **If macOS blocks the app, run this in Terminal:**
```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNext.app
```
**Why**: I can't afford Apple's developer certificate ($99/year), so macOS blocks unsigned apps. This command removes the quarantine flag to let it run. **Only use this command on apps you trust.**

### What LaunchNext Delivers
- ✅ **One-click import from old system Launchpad** - directly reads your native Launchpad SQLite database (`/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db`) to perfectly recreate your existing folders, app positions, and layout
- ✅ **Classic Launchpad experience** - works exactly like the beloved original interface
- ✅ **Multi-language support** - full internationalization with English, Chinese, Japanese, French, Spanish, German, Russian, and more
- ✅ **Hide icon labels** - clean, minimalist view when you don't need app names
- ✅ **Custom icon sizes** - adjust icon dimensions to fit your preferences
- ✅ **Smart folder management** - create and organize folders just like before
- ✅ **Instant search and keyboard navigation** - find apps quickly
- ✅ **CLI / TUI support** - inspect and operate your layout from the terminal
- ✅ **Hot Corner and native gesture support** - more ways to open LaunchNext quickly
- ✅ **Drag apps directly to the Dock** - available in Next Engine + Core Animation
- ✅ **Update tab with Markdown release notes** - richer in-app update experience
- ✅ **Backup, controller, and voice support improvements** - better reliability and accessibility

### What We Lost in macOS Tahoe
- ❌ No custom app organization
- ❌ No user-created folders
- ❌ No drag-and-drop customization
- ❌ No visual app management
- ❌ Forced categorical grouping


### Data Storage
Application data is safely stored in:
```
~/Library/Application Support/LaunchNext/Data.store
```

### Native Launchpad Integration
Reads directly from the system Launchpad database:
```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Installation

### Requirements
- macOS 26 (Tahoe) or later
- Apple Silicon or Intel processor
- Xcode 26 (for building from source)

### Build from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/RoversX/LaunchNext.git
   cd LaunchNext
   ```

2. **Open in Xcode**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **Build and run**
   - Select your target device
   - Press `⌘+R` to build and run
   - Or `⌘+B` to build only

### Command Line Build

**Regular Build:**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**Universal Binary Build (Intel + Apple Silicon):**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Usage

### Getting Started
1. **First Launch**: LaunchNext automatically scans all installed applications
2. **Select**: Click to select apps, double-click to launch
3. **Search**: Type to instantly filter applications
4. **Organize**: Drag apps to create folders and custom layouts
5. **Automate**: Enable CLI in Settings if you want terminal workflows

### Import Your Launchpad
1. Open Settings (gear icon)
2. Click **"Import Launchpad"**
3. Your existing layout and folders are automatically imported


### Display Modes
- **Compact**: Floating window with rounded corners
- **Fullscreen**: Full-screen mode for maximum visibility
- **Legacy Engine** and **Next Engine + Core Animation** are available in Settings
- LaunchNext can keep separate settings for fullscreen and compact

## Advanced Features

### Smart Background Interaction
- Intelligent click detection prevents accidental dismissal
- Context-aware gesture handling
- Search field protection

### Performance Optimization
- **Icon Caching**: Intelligent image caching for smooth scrolling
- **Lazy Loading**: Efficient memory usage
- **Background Scanning**: Non-blocking app discovery

### Automation and Activation
- **CLI / TUI**: Manage LaunchNext from the terminal
- **Hot Corner**: Open LaunchNext from a configurable screen corner
- **Experimental native gestures**: Four-finger pinch / tap actions
- **Dock drag**: Drag apps directly into the macOS Dock in Next Engine + Core Animation

### Update and Backup Tools
- **Update tab**: Check for updates and read Markdown release notes inside Settings
- **Backup tools**: Create and restore backups more safely
- **Notification update**: Modern notification API support

### Multi-Display Support
- Automatic screen detection
- Per-display positioning
- Seamless multi-monitor workflows

## Troubleshooting

### Common Issues

**Q: App won't start?**
A: Ensure macOS 26.0+ and check system permissions.

**Q: Which engine should I use?**
A: `Next Engine + Core Animation` is recommended for the best experience. `Legacy Engine` is still available if you need the older compatibility path.

**Q: Why doesn't the CLI command exist yet?**
A: Enable the command line interface in Settings first. LaunchNext can install and remove the managed `launchnext` command for you.

## Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines
- Follow Swift style conventions
- Add meaningful comments for complex logic
- Test on multiple macOS versions
- Maintain backward compatibility

## The Future of App Management

As Apple moves away from customizable interfaces, LaunchNext represents a push toward user control and personalization. I still hope Apple brings Launchpad back.

**LaunchNext** isn't just a Launchpad replacement—it's a statement that user choice matters.


---

**LaunchNext** - Reclaim Your App Launcher 🚀

*Built for macOS users who refuse to compromise on customization.*

## Development Tools

- Claude Code 
- Cursor 
- OpenAI Codex CLI
- Perplexity
- Google



- Experimental gesture support is built on [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) and the fork by [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).❤️


![GitHub downloads](https://img.shields.io/github/downloads/RoversX/LaunchNext/total)
