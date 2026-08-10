# SwiftUpdater

SwiftUpdater is the Swift-based command line updater used by LaunchNext. It replaces the previous Python script and provides the same functionality with localized UI, interactive ncurses prompts, and non-interactive automation flags.

## Building

Requirements: Xcode 16+ (Swift 6 toolchain) on macOS 15 or newer.

```bash
cd UpdaterScripts/SwiftUpdater
swift build --configuration release --arch arm64 --arch x86_64 --product SwiftUpdater
```

The universal binary will be available at:

```
UpdaterScripts/SwiftUpdater/.build/apple/Products/Release/SwiftUpdater
```

Keep this path intact so the Xcode Run Script phase can copy and sign the binary into the app bundle. If the `.build` directory is removed or you are on a new machine, re-run the `swift build` command above.

## Usage

From the terminal you can invoke the updater directly:

```bash
./SwiftUpdater --help
```

Key flags:

- `--tag <release>` – install a specific GitHub release tag
- `--asset-pattern <regex>` – filter release assets (defaults to `LaunchNext.*\.zip`)
- `--install-dir <path>` – target installation directory (defaults to `/Applications/LaunchNext.app`)
- `--download-only` – download the bundle into the cache without installing
- `--yes` – non-interactive mode (assume yes to prompts)
- `--language <code>` – force a language; run without it for the interactive menu
- `--hold-window` – keep the terminal window open and wait for Enter before exit

Localization data and user preferences are stored under:

```
~/Library/Application Support/LaunchNext/updates/config.json
```

## ncurses UI

When run interactively (terminal attached), the updater launches an ncurses interface that lets users:

- choose language (arrow keys or number keys `1-0` for quick selection)
- confirm whether to proceed or download-only
- view live download progress and logs

If keyboard controls fail, the updater can fall back to non-interactive mode with `--yes`.

## Integration with LaunchNext

The main app bundles the compiled SwiftUpdater at:

```
LaunchNext.app/Contents/Resources/Updater/SwiftUpdater
```

During build, the `Run Script (Updater)` phase copies the binary from `.build/.../SwiftUpdater`, signs it with Xcode's active signing identity and Hardened Runtime, and packages it with the app. Builds without an available signing identity fall back to an ad-hoc Hardened Runtime signature.

The settings UI triggers the updater via Terminal using `/usr/bin/open -na Terminal --args ... SwiftUpdater` so that the user sees progress and can authenticate with sudo.

## Troubleshooting

- **Binary missing at build time** – run the `swift build` command above to regenerate `.build/apple/Products/Release/SwiftUpdater`.
- **Terminal says “killed”** – ensure the binary is copied during build and is code-signed. The Run Script phase handles this automatically.
- **Need to rebuild** – whenever you change SwiftUpdater’s code, repeat the build command. The next app build will package the new binary.
