import AppKit
import Foundation

enum QuarantineRemovalTerminalLauncher {
    enum LaunchError: Error {
        case invalidTarget
        case scriptCreationFailed
        case terminalUnavailable
        case terminalLaunchFailed
    }

    struct Messages {
        let targetLabel: String
        let commandLabel: String
        let success: String
        let failure: String
        let exitStatusLabel: String
        let pressReturn: String
    }

    struct PreparedLaunch {
        let scriptURL: URL
        let terminalURL: URL
    }

    static func validatedAppURL(for inputURL: URL) throws -> URL {
        guard inputURL.isFileURL else { throw LaunchError.invalidTarget }

        let resolvedURL = inputURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedURL.path.hasPrefix("/"),
              resolvedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            throw LaunchError.invalidTarget
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              Bundle(url: resolvedURL) != nil else {
            throw LaunchError.invalidTarget
        }

        return resolvedURL
    }

    static func command(for appURL: URL) -> String {
        "/usr/bin/sudo /usr/bin/xattr -r -d com.apple.quarantine \(shellQuote(appURL.path))"
    }

    static func prepareLaunch(for appURL: URL, messages: Messages) throws -> PreparedLaunch {
        let validatedURL = try validatedAppURL(for: appURL)
        guard validatedURL == appURL.standardizedFileURL else {
            throw LaunchError.invalidTarget
        }

        let expectedIdentity = try fileIdentity(for: validatedURL)
        guard let terminalURL = systemTerminalURL() else {
            throw LaunchError.terminalUnavailable
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchNext-Quarantine-\(UUID().uuidString)")
            .appendingPathExtension("command")
        let commandText = command(for: validatedURL)
        let script = """
        #!/bin/zsh
        /bin/rm -f \(shellQuote(scriptURL.path))
        target=\(shellQuote(validatedURL.path))
        expected_identity=\(shellQuote(expectedIdentity))

        /usr/bin/printf '%s %s\\n' \(shellQuote(messages.targetLabel)) "$target"
        /usr/bin/printf '%s %s\\n\\n' \(shellQuote(messages.commandLabel)) \(shellQuote(commandText))

        actual_identity=$(/usr/bin/stat -f '%d:%i' "$target" 2>/dev/null)
        if [[ -L "$target" || ! -d "$target" || "$actual_identity" != "$expected_identity" ]]; then
            /usr/bin/printf '%s\\n' \(shellQuote(messages.failure))
            /usr/bin/printf '%s %s\\n' \(shellQuote(messages.exitStatusLabel)) "1"
            /usr/bin/printf '\\n%s' \(shellQuote(messages.pressReturn))
            IFS= read -r _
            exit 1
        fi

        /usr/bin/sudo /usr/bin/xattr -r -d com.apple.quarantine "$target"
        exit_code=$?

        /usr/bin/printf '\\n'
        if [[ $exit_code -eq 0 ]]; then
            /usr/bin/printf '%s\\n' \(shellQuote(messages.success))
        else
            /usr/bin/printf '%s\\n' \(shellQuote(messages.failure))
            /usr/bin/printf '%s %s\\n' \(shellQuote(messages.exitStatusLabel)) "$exit_code"
        fi

        /usr/bin/printf '\\n%s' \(shellQuote(messages.pressReturn))
        IFS= read -r _
        exit "$exit_code"
        """

        do {
            try Data(script.utf8).write(to: scriptURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o700))],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
            throw LaunchError.scriptCreationFailed
        }

        return PreparedLaunch(scriptURL: scriptURL, terminalURL: terminalURL)
    }

    @MainActor
    static func open(
        _ launch: PreparedLaunch,
        completion: @escaping (Result<Void, LaunchError>) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [launch.scriptURL],
            withApplicationAt: launch.terminalURL,
            configuration: configuration
        ) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    completion(.success(()))
                } else {
                    try? FileManager.default.removeItem(at: launch.scriptURL)
                    completion(.failure(.terminalLaunchFailed))
                }
            }
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func fileIdentity(for url: URL) throws -> String {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw LaunchError.invalidTarget
        }

        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw LaunchError.invalidTarget
        }
        return "\(device.uint64Value):\(inode.uint64Value)"
    }

    private static func systemTerminalURL() -> URL? {
        if let registeredURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            return registeredURL
        }

        let fallbackURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app", isDirectory: true)
        return FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil
    }
}
