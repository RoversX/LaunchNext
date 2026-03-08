import Foundation
import Darwin

enum LaunchNextCLICommandResult {
    case success(String)
    case failure(String)
}

struct LaunchNextCLIRequest {
    let command: String
    let arguments: [String: String]

    init(command: String, arguments: [String: String] = [:]) {
        self.command = command
        self.arguments = arguments
    }
}

struct LaunchNextCLIContext {
    let executeRemoteCommand: ((LaunchNextCLIRequest) -> LaunchNextCLICommandResult)?

    init(executeRemoteCommand: ((LaunchNextCLIRequest) -> LaunchNextCLICommandResult)? = nil) {
        self.executeRemoteCommand = executeRemoteCommand
    }
}

enum LaunchNextRuntimeMode {
    case gui
    case tui
    case cli
}

struct LaunchNextCLIArguments {
    let mode: LaunchNextRuntimeMode
    let command: String?
    let commandArguments: [String]

    static func parse(_ arguments: [String] = CommandLine.arguments) -> LaunchNextCLIArguments {
        let rawArgs = Array(arguments.dropFirst())
        // Ignore LaunchServices-injected args when app starts from Finder (e.g. "-psn_0_12345").
        let args = rawArgs.filter { arg in
            !arg.hasPrefix("-psn_")
        }
        guard let first = args.first else {
            // No args: interactive terminal enters TUI; otherwise keep normal GUI launch behavior.
            if isInteractiveTerminalSession() {
                return LaunchNextCLIArguments(mode: .tui, command: nil, commandArguments: [])
            }
            return LaunchNextCLIArguments(mode: .gui, command: nil, commandArguments: [])
        }

        switch first {
        case "--gui":
            return LaunchNextCLIArguments(mode: .gui, command: nil, commandArguments: [])
        case "--tui":
            return LaunchNextCLIArguments(mode: .tui, command: nil, commandArguments: [])
        case "--cli":
            let command = args.dropFirst().first
            let commandArgs = Array(args.dropFirst(2))
            return LaunchNextCLIArguments(mode: .cli, command: command, commandArguments: commandArgs)
        case "help", "--help", "-h":
            return LaunchNextCLIArguments(mode: .cli, command: "help", commandArguments: [])
        default:
            if first.hasPrefix("-") {
                // Unknown flag should not force app into CLI mode.
                return LaunchNextCLIArguments(mode: .gui, command: nil, commandArguments: [])
            }
            return LaunchNextCLIArguments(mode: .cli, command: first, commandArguments: Array(args.dropFirst()))
        }
    }

    private static func isInteractiveTerminalSession() -> Bool {
        isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    }
}

enum LaunchNextCLI {
    private static let cliHistoryMaxCount = 200

    @discardableResult
    static func run(parsed: LaunchNextCLIArguments = .parse(), context: LaunchNextCLIContext = LaunchNextCLIContext()) -> Int32 {
        switch parsed.mode {
        case .gui:
            return 0
        case .tui:
            return runTUI(context: context)
        case .cli:
            appendCLIHistoryEntry(command: parsed.command ?? "help", commandArguments: parsed.commandArguments)
            switch parsed.command {
            case nil, "help":
                printHelp()
                return 0
            case "list":
                return runRemoteCommand("list", context: context)
            case "snapshot":
                return runRemoteCommand("snapshot", context: context)
            case "history":
                return runHistory(commandArguments: parsed.commandArguments)
            case "example":
                printCLIExamples()
                return 0
            case "search":
                return runSearch(commandArguments: parsed.commandArguments, context: context)
            case "create-folder":
                return runCreateFolder(commandArguments: parsed.commandArguments, context: context)
            case "move":
                return runMove(commandArguments: parsed.commandArguments, context: context)
            default:
                fputs("LaunchNext CLI: command not implemented yet.\n", stderr)
                printHelp()
                return 1
            }
        }
    }

    static func printHelp() {
        let text = """
        LaunchNext CLI

        Usage:
          launchnext
          launchnext --gui
          launchnext --tui
          launchnext --cli list
          launchnext --cli snapshot
          launchnext --cli history
          launchnext --cli history --limit 20
          launchnext --cli example
          launchnext --cli search --query "safari"
          launchnext --cli search safari
          launchnext --cli create-folder --path "/Applications/Mail.app" --path "/Applications/Notes.app" [--name "Utilities"] [--index 12] [--dry-run]
          launchnext --cli move --source normal-app --path \"/Applications/Safari.app\" --to normal-index --index 12 [--dry-run]
          launchnext --cli move --source normal-app --path \"/Applications/Safari.app\" --to folder-append --target-folder-id <folder-id> [--dry-run]
          launchnext --cli move --source folder-app --folder-id <folder-id> --path \"/Applications/Safari.app\" --to folder-index --target-folder-id <folder-id> --index 0 [--dry-run]
          launchnext --cli help
          launchnext list
          launchnext snapshot
          launchnext search --query "mail"
          launchnext help

        Commands:
          list
            Print a flat app list from the running GUI instance.
          snapshot
            Print full layout snapshot JSON.
            Use this output to read folder IDs for move commands.
          history
            Print saved CLI/TUI command history.
            Options: [--limit <n>] or [<n>]
          example
            Print CLI/TUI example commands.
          search
            Search apps/folders by name or path.
            Options: --query <text> | <text>, [--limit <n>], [--json]
          create-folder
            Create a new folder from top-level apps.
            Options: --path <app-path> (repeat at least twice), [--name <folder-name>], [--index <n>], [--dry-run]
            Only top-level apps are supported. Apps inside folders are not supported yet.
          move
            Apply layout changes in the running GUI instance.
            --source: normal-app | folder-app
            --to: normal-index | folder-append | folder-index
            Required by target:
              normal-index -> --index <n>
              folder-append -> --target-folder-id <id>
              folder-index -> --target-folder-id <id> --index <n>
            Source folder app also needs: --folder-id <id>

        Requirements:
          - LaunchNext GUI must be running for list/snapshot/search/create-folder/move.
          - history/help do not require GUI.
          - "Command line interface" must be ON in General settings.
          - `launchnext` (without args) enters TUI only in interactive terminal sessions.
          - non-interactive sessions default to GUI unless explicit `--cli` is used.

        Agent / non-interactive quick start:
          launchnext --cli help
          launchnext --cli list
          launchnext --cli snapshot
          launchnext --cli search --query "safari"
          launchnext --cli move --source normal-app --path "/Applications/Thaw.app" --to folder-append --target-folder-id <folder-id>
        """
        print(text)
    }

    @discardableResult
    private static func runTUI(context: LaunchNextCLIContext) -> Int32 {
        if isatty(STDIN_FILENO) == 0 {
            fputs("LaunchNext TUI requires an interactive terminal.\n", stderr)
            return 1
        }
        let connectivityStatus = runRemoteCommand("ping", context: context, printOutput: false)
        if connectivityStatus != 0 {
            return connectivityStatus
        }

        printTUIBanner()
        print("LaunchNext TUI")
        print("Version: \(appVersionString())")
        print("Type 'help' for commands.")

        var lineEditor = TUILineEditor(prompt: "launchnext> ",
                                       historyPath: cliHistoryFilePath(),
                                       maxHistoryCount: cliHistoryMaxCount)
        lineEditor.loadHistory()
        defer { lineEditor.saveHistory() }

        while true {
            guard let line = lineEditor.readLine() else {
                print("\nExit.")
                return 0
            }

            let input = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty { continue }
            lineEditor.addHistory(input)
            lineEditor.saveHistory()

            let commandTokensResult = tokenizeCommandLine(input)
            let commandTokens: [String]
            switch commandTokensResult {
            case .failure(let message):
                print(message)
                continue
            case .success(let tokens):
                commandTokens = tokens
            }
            guard let command = commandTokens.first?.lowercased() else { continue }
            let commandArguments = Array(commandTokens.dropFirst())

            switch command {
            case "help", "?":
                print([
                    "Commands:",
                    "  list      Show app list",
                    "  snapshot  Show layout snapshot (JSON)",
                    "  history   Show saved CLI/TUI command history",
                    "  example   Show CLI/TUI example commands",
                    "  search    Search apps/folders by name or path",
                    "  create-folder  Create folder from top-level apps only",
                    "  move      Move apps/folder-apps by path and target",
                    "  clear     Clear the terminal screen",
                    "  help      Show this help",
                    "  quit      Exit TUI"
                ].joined(separator: "\n"))
                print("Use 'example' to see usage examples.")
            case "list":
                let status = runRemoteCommand("list", context: context)
                if status != 0 { return status }
            case "snapshot":
                let status = runRemoteCommand("snapshot", context: context)
                if status != 0 { return status }
            case "history":
                _ = runHistory(commandArguments: commandArguments)
            case "example":
                printTUIExamples()
            case "search":
                if commandArguments.isEmpty {
                    print([
                        "Usage:",
                        "  search --query \"<text>\" [--limit <n>] [--json]",
                        "  search <text>"
                    ].joined(separator: "\n"))
                    continue
                }
                _ = runSearch(commandArguments: commandArguments, context: context)
            case "create-folder":
                if commandArguments.isEmpty {
                    print([
                        "Usage:",
                        "  create-folder --path \"<app-path>\" --path \"<app-path>\" [--name \"<folder-name>\"] [--index <n>] [--dry-run]",
                        "  (top-level apps only; apps inside folders are not supported)"
                    ].joined(separator: "\n"))
                    continue
                }
                _ = runCreateFolder(commandArguments: commandArguments, context: context)
            case "move":
                if commandArguments.isEmpty {
                    print([
                        "Usage:",
                        "  move --source normal-app|folder-app --path \"<app-path>\" --to normal-index|folder-append|folder-index [--index <n>] [--folder-id <id>] [--target-folder-id <id>] [--dry-run]"
                    ].joined(separator: "\n"))
                    continue
                }
                _ = runMove(commandArguments: commandArguments, context: context)
            case "clear", "cls":
                clearTerminalScreen()
            case "quit", "exit", "q":
                print("Bye.")
                return 0
            default:
                print("Unknown command: \(command)")
            }
        }
    }

    @discardableResult
    private static func runRemoteCommand(_ command: String, context: LaunchNextCLIContext, printOutput: Bool = true, arguments: [String: String] = [:]) -> Int32 {
        guard let execute = context.executeRemoteCommand else {
            fputs("LaunchNext CLI endpoint is unavailable.\n", stderr)
            return 1
        }
        switch execute(LaunchNextCLIRequest(command: command, arguments: arguments)) {
        case .success(let output):
            if printOutput && !output.isEmpty {
                print(output)
            }
            return 0
        case .failure(let message):
            fputs("\(message)\n", stderr)
            return 1
        }
    }

    @discardableResult
    private static func runMove(commandArguments: [String], context: LaunchNextCLIContext) -> Int32 {
        let parsed = parseMoveArguments(commandArguments)
        switch parsed {
        case .failure(let message):
            fputs("Move command error: \(message)\n", stderr)
            fputs("Try: --cli move --source normal-app --path \"/Applications/Safari.app\" --to normal-index --index 12\n", stderr)
            return 1
        case .success(let arguments):
            return runRemoteCommand("move", context: context, arguments: arguments)
        }
    }

    @discardableResult
    private static func runSearch(commandArguments: [String], context: LaunchNextCLIContext) -> Int32 {
        let parsed = parseSearchArguments(commandArguments)
        switch parsed {
        case .failure(let message):
            fputs("Search command error: \(message)\n", stderr)
            fputs("Try: --cli search --query \"safari\"\n", stderr)
            return 1
        case .success(let arguments):
            return runRemoteCommand("search", context: context, arguments: arguments)
        }
    }

    @discardableResult
    private static func runCreateFolder(commandArguments: [String], context: LaunchNextCLIContext) -> Int32 {
        let parsed = parseCreateFolderArguments(commandArguments)
        switch parsed {
        case .failure(let message):
            fputs("Create-folder command error: \(message)\n", stderr)
            fputs("Try: --cli create-folder --path \"/Applications/Mail.app\" --path \"/Applications/Notes.app\"\n", stderr)
            return 1
        case .success(let arguments):
            return runRemoteCommand("create-folder", context: context, arguments: arguments)
        }
    }

    @discardableResult
    private static func runHistory(commandArguments: [String]) -> Int32 {
        let parseResult = parseHistoryArguments(commandArguments)
        let limit: Int?
        switch parseResult {
        case .failure(let message):
            fputs("History command error: \(message)\n", stderr)
            fputs("Try: --cli history --limit 20\n", stderr)
            return 1
        case .success(let options):
            limit = options["limit"].flatMap(Int.init)
        }

        guard let historyPath = cliHistoryFilePath() else {
            fputs("History is unavailable: cannot resolve history file path.\n", stderr)
            return 1
        }

        let entries = loadHistoryEntries(from: historyPath)
        guard !entries.isEmpty else {
            print("No CLI/TUI history yet.")
            return 0
        }

        let displayCount = min(limit ?? entries.count, entries.count)
        let startIndex = entries.count - displayCount
        for index in startIndex..<entries.count {
            print(String(format: "%4d  %@", index + 1, entries[index]))
        }
        return 0
    }

    private enum CLIArgumentParseResult {
        case success([String: String])
        case failure(String)
    }

    private static func parseMoveArguments(_ rawArguments: [String]) -> CLIArgumentParseResult {
        let parse = parseLongOptionArguments(rawArguments)
        guard case .success(let options) = parse else { return parse }

        guard let sourceType = options["source"] else {
            return .failure("Missing --source.")
        }
        guard sourceType == "normal-app" || sourceType == "folder-app" else {
            return .failure("Unsupported --source value: \(sourceType)")
        }
        guard let destinationType = options["to"] else {
            return .failure("Missing --to.")
        }
        guard destinationType == "normal-index" || destinationType == "folder-append" || destinationType == "folder-index" else {
            return .failure("Unsupported --to value: \(destinationType)")
        }

        var requestArguments: [String: String] = [
            "sourceType": sourceType,
            "destinationType": destinationType
        ]

        if options["dry-run"] == "true" {
            requestArguments["dryRun"] = "true"
        } else {
            requestArguments["dryRun"] = "false"
        }

        guard let sourcePath = options["path"], !sourcePath.isEmpty else {
            return .failure("Missing --path.")
        }
        requestArguments["sourcePath"] = sourcePath

        if sourceType == "folder-app" {
            guard let sourceFolderID = options["folder-id"], !sourceFolderID.isEmpty else {
                return .failure("folder-app requires --folder-id.")
            }
            requestArguments["sourceFolderID"] = sourceFolderID
        }

        switch destinationType {
        case "normal-index":
            guard let rawIndex = options["index"], let index = Int(rawIndex), index >= 0 else {
                return .failure("normal-index requires a non-negative --index.")
            }
            requestArguments["destinationIndex"] = String(index)
        case "folder-append":
            let targetFolder = options["target-folder-id"] ?? (sourceType == "normal-app" ? options["folder-id"] : nil)
            guard let destinationFolderID = targetFolder, !destinationFolderID.isEmpty else {
                return .failure("folder-append requires --target-folder-id.")
            }
            requestArguments["destinationFolderID"] = destinationFolderID
        case "folder-index":
            guard let rawIndex = options["index"], let index = Int(rawIndex), index >= 0 else {
                return .failure("folder-index requires a non-negative --index.")
            }
            let targetFolder = options["target-folder-id"] ?? (sourceType == "folder-app" ? options["folder-id"] : nil)
            guard let destinationFolderID = targetFolder, !destinationFolderID.isEmpty else {
                return .failure("folder-index requires --target-folder-id.")
            }
            requestArguments["destinationFolderID"] = destinationFolderID
            requestArguments["destinationIndex"] = String(index)
        default:
            return .failure("Unsupported destination.")
        }

        return .success(requestArguments)
    }

    private static func parseSearchArguments(_ rawArguments: [String]) -> CLIArgumentParseResult {
        guard !rawArguments.isEmpty else {
            return .failure("Missing search query.")
        }

        var requestArguments: [String: String] = [:]

        if rawArguments.first?.hasPrefix("--") == true {
            let parse = parseLongOptionArguments(rawArguments)
            guard case .success(let options) = parse else { return parse }

            let query = (options["query"] ?? options["q"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                return .failure("Missing --query.")
            }
            requestArguments["query"] = query

            if let rawLimit = options["limit"] {
                guard let limit = Int(rawLimit), limit > 0 else {
                    return .failure("Invalid --limit value: \(rawLimit)")
                }
                requestArguments["limit"] = String(limit)
            }

            if options["json"] == "true" {
                requestArguments["format"] = "json"
            }
        } else {
            let query = rawArguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                return .failure("Missing search query.")
            }
            requestArguments["query"] = query
        }

        return .success(requestArguments)
    }

    private static func parseCreateFolderArguments(_ rawArguments: [String]) -> CLIArgumentParseResult {
        guard !rawArguments.isEmpty else {
            return .failure("Missing create-folder arguments.")
        }

        var paths: [String] = []
        var folderName: String?
        var destinationIndex: Int?
        var dryRun = false

        var index = 0
        while index < rawArguments.count {
            let token = rawArguments[index]
            guard token.hasPrefix("--"), token.count > 2 else {
                return .failure("Unexpected token: \(token)")
            }

            let key = String(token.dropFirst(2))
            switch key {
            case "path":
                guard index + 1 < rawArguments.count else {
                    return .failure("Missing value for --path.")
                }
                let path = rawArguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else {
                    return .failure("Path value cannot be empty.")
                }
                paths.append(path)
                index += 2
            case "name":
                guard index + 1 < rawArguments.count else {
                    return .failure("Missing value for --name.")
                }
                folderName = rawArguments[index + 1]
                index += 2
            case "index":
                guard index + 1 < rawArguments.count else {
                    return .failure("Missing value for --index.")
                }
                let rawIndex = rawArguments[index + 1]
                guard let parsed = Int(rawIndex), parsed >= 0 else {
                    return .failure("Invalid --index value: \(rawIndex)")
                }
                destinationIndex = parsed
                index += 2
            case "dry-run":
                dryRun = true
                index += 1
            default:
                return .failure("Unsupported option for create-folder: --\(key)")
            }
        }

        if paths.count < 2 {
            return .failure("create-folder requires at least two --path values.")
        }

        guard let pathsData = try? JSONEncoder().encode(paths),
              let pathsJSON = String(data: pathsData, encoding: .utf8) else {
            return .failure("Failed to encode create-folder paths.")
        }

        var arguments: [String: String] = [
            "appPathsJSON": pathsJSON,
            "dryRun": dryRun ? "true" : "false"
        ]
        if let folderName {
            arguments["folderName"] = folderName
        }
        if let destinationIndex {
            arguments["destinationIndex"] = String(destinationIndex)
        }
        return .success(arguments)
    }

    private static func parseHistoryArguments(_ rawArguments: [String]) -> CLIArgumentParseResult {
        guard !rawArguments.isEmpty else {
            return .success([:])
        }

        if rawArguments.first?.hasPrefix("--") == true {
            let parse = parseLongOptionArguments(rawArguments)
            guard case .success(let options) = parse else { return parse }
            guard options.count <= 1 else {
                return .failure("Only --limit is supported.")
            }
            if let rawLimit = options["limit"] {
                guard let limit = Int(rawLimit), limit > 0 else {
                    return .failure("Invalid --limit value: \(rawLimit)")
                }
                return .success(["limit": String(limit)])
            }
            return .failure("Unsupported option. Use --limit <n>.")
        }

        guard rawArguments.count == 1, let limit = Int(rawArguments[0]), limit > 0 else {
            return .failure("Expected a positive number or --limit <n>.")
        }
        return .success(["limit": String(limit)])
    }

    private static func parseLongOptionArguments(_ rawArguments: [String]) -> CLIArgumentParseResult {
        var options: [String: String] = [:]
        let flagOnlyOptions: Set<String> = ["dry-run", "json"]
        var index = 0
        while index < rawArguments.count {
            let token = rawArguments[index]
            guard token.hasPrefix("--"), token.count > 2 else {
                return .failure("Unexpected token: \(token)")
            }

            let key = String(token.dropFirst(2))
            if flagOnlyOptions.contains(key) {
                options[key] = "true"
                index += 1
                continue
            }

            guard index + 1 < rawArguments.count else {
                return .failure("Missing value for \(token)")
            }
            let value = rawArguments[index + 1]
            options[key] = value
            index += 2
        }
        return .success(options)
    }

    private static func loadHistoryEntries(from historyPath: String) -> [String] {
        guard let content = try? String(contentsOfFile: historyPath, encoding: .utf8) else {
            return []
        }
        let lines = content.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return Array(lines.suffix(cliHistoryMaxCount))
    }

    private static func appendCLIHistoryEntry(command: String, commandArguments: [String]) {
        guard let historyPath = cliHistoryFilePath() else { return }

        let commandName = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandName.isEmpty else { return }

        var tokens = [commandName]
        for argument in commandArguments {
            if argument.contains(" ") {
                tokens.append("\"\(argument)\"")
            } else {
                tokens.append(argument)
            }
        }
        let entry = tokens.joined(separator: " ")

        var lines = loadHistoryEntries(from: historyPath)
        if lines.last == entry { return }
        lines.append(entry)
        if lines.count > cliHistoryMaxCount {
            lines.removeFirst(lines.count - cliHistoryMaxCount)
        }
        let serialized = lines.joined(separator: "\n")
        try? serialized.write(toFile: historyPath, atomically: true, encoding: .utf8)
    }

    private static func cliHistoryFilePath() -> String? {
        let fileManager = FileManager.default
        guard let appSupport = try? fileManager.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: true) else {
            return nil
        }
        let directory = appSupport.appendingPathComponent("LaunchNext", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("cli_history", isDirectory: false).path
    }

    private struct TUILineEditor {
        private enum InputKey {
            case character(Character)
            case enter
            case backspace
            case delete
            case left
            case right
            case up
            case down
            case home
            case end
            case clearScreen
            case interrupt
            case eof
        }

        let prompt: String
        let historyPath: String?
        let maxHistoryCount: Int
        private var history: [String] = []

        init(prompt: String, historyPath: String?, maxHistoryCount: Int = 500) {
            self.prompt = prompt
            self.historyPath = historyPath
            self.maxHistoryCount = maxHistoryCount
        }

        mutating func loadHistory() {
            guard let historyPath else { return }
            guard let content = try? String(contentsOfFile: historyPath, encoding: .utf8) else { return }
            let lines = content.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            history = Array(lines.suffix(maxHistoryCount))
        }

        func saveHistory() {
            guard let historyPath else { return }
            let trimmed = Array(history.suffix(maxHistoryCount))
            let serialized = trimmed.joined(separator: "\n")
            try? serialized.write(toFile: historyPath, atomically: true, encoding: .utf8)
        }

        mutating func addHistory(_ input: String) {
            let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            if history.last == value { return }
            history.append(value)
            if history.count > maxHistoryCount {
                history.removeFirst(history.count - maxHistoryCount)
            }
        }

        mutating func readLine() -> String? {
            var original = termios()
            guard tcgetattr(STDIN_FILENO, &original) == 0 else {
                return Swift.readLine(strippingNewline: true)
            }

            var raw = original
            raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
            raw.c_oflag &= ~tcflag_t(OPOST)
            raw.c_cflag |= tcflag_t(CS8)
            // Disable ISIG so Ctrl-C is handled in-process instead of killing TUI
            // while the terminal is in raw mode.
            raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
            withUnsafeMutableBytes(of: &raw.c_cc) { ccBytes in
                let vmin = Int(VMIN)
                let vtime = Int(VTIME)
                if vmin >= 0 && vmin < ccBytes.count {
                    ccBytes[vmin] = 1
                }
                if vtime >= 0 && vtime < ccBytes.count {
                    ccBytes[vtime] = 0
                }
            }

            guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
                return Swift.readLine(strippingNewline: true)
            }
            defer {
                var restored = original
                _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &restored)
            }

            var buffer: [Character] = []
            var cursor = 0
            var historyIndex: Int?
            var draftBeforeHistory: [Character] = []
            var hasDraftBeforeHistory = false

            render(buffer: buffer, cursor: cursor)

            while true {
                guard let key = readKey() else { continue }

                switch key {
                case .character(let character):
                    historyIndex = nil
                    hasDraftBeforeHistory = false
                    buffer.insert(character, at: cursor)
                    cursor += 1
                    render(buffer: buffer, cursor: cursor)

                case .enter:
                    let output = String(buffer)
                    fputs("\r\(prompt)\(output)\u{001B}[K\r\n", stdout)
                    fflush(stdout)
                    return output

                case .backspace:
                    guard cursor > 0 else {
                        beep()
                        continue
                    }
                    historyIndex = nil
                    hasDraftBeforeHistory = false
                    buffer.remove(at: cursor - 1)
                    cursor -= 1
                    render(buffer: buffer, cursor: cursor)

                case .delete:
                    guard cursor < buffer.count else {
                        beep()
                        continue
                    }
                    historyIndex = nil
                    hasDraftBeforeHistory = false
                    buffer.remove(at: cursor)
                    render(buffer: buffer, cursor: cursor)

                case .left:
                    guard cursor > 0 else {
                        beep()
                        continue
                    }
                    cursor -= 1
                    render(buffer: buffer, cursor: cursor)

                case .right:
                    guard cursor < buffer.count else {
                        beep()
                        continue
                    }
                    cursor += 1
                    render(buffer: buffer, cursor: cursor)

                case .home:
                    cursor = 0
                    render(buffer: buffer, cursor: cursor)

                case .end:
                    cursor = buffer.count
                    render(buffer: buffer, cursor: cursor)

                case .up:
                    guard !history.isEmpty else {
                        beep()
                        continue
                    }
                    if historyIndex == nil {
                        draftBeforeHistory = buffer
                        hasDraftBeforeHistory = true
                        historyIndex = history.count - 1
                    } else if let currentIndex = historyIndex, currentIndex > 0 {
                        historyIndex = currentIndex - 1
                    } else {
                        beep()
                    }
                    if let currentIndex = historyIndex {
                        buffer = Array(history[currentIndex])
                        cursor = buffer.count
                        render(buffer: buffer, cursor: cursor)
                    }

                case .down:
                    guard !history.isEmpty else {
                        beep()
                        continue
                    }
                    guard let currentIndex = historyIndex else {
                        beep()
                        continue
                    }
                    if currentIndex < history.count - 1 {
                        let nextIndex = currentIndex + 1
                        historyIndex = nextIndex
                        buffer = Array(history[nextIndex])
                    } else {
                        historyIndex = nil
                        buffer = hasDraftBeforeHistory ? draftBeforeHistory : []
                        hasDraftBeforeHistory = false
                    }
                    cursor = buffer.count
                    render(buffer: buffer, cursor: cursor)

                case .clearScreen:
                    LaunchNextCLI.clearTerminalScreen()
                    render(buffer: buffer, cursor: cursor)

                case .interrupt:
                    fputs("^C\r\n", stdout)
                    fflush(stdout)
                    return ""

                case .eof:
                    if buffer.isEmpty {
                        return nil
                    }
                    if cursor < buffer.count {
                        buffer.remove(at: cursor)
                        render(buffer: buffer, cursor: cursor)
                    } else {
                        beep()
                    }
                }
            }
        }

        private func readByte() -> UInt8? {
            var byte: UInt8 = 0
            while true {
                let result = read(STDIN_FILENO, &byte, 1)
                if result == 1 { return byte }
                if result == 0 { return nil }
                if result == -1 && errno == EINTR { continue }
                return nil
            }
        }

        private func readKey() -> InputKey? {
            guard let byte = readByte() else { return .eof }
            switch byte {
            case 0x0D, 0x0A: return .enter
            case 0x7F, 0x08: return .backspace
            case 0x04: return .eof
            case 0x01: return .home
            case 0x05: return .end
            case 0x0C: return .clearScreen
            case 0x03: return .interrupt
            case 0x1B: return readEscapeKey()
            default:
                if byte < 0x20 { return nil }
                if byte < 0x80 {
                    return .character(Character(UnicodeScalar(byte)))
                }
                if let character = readUTF8Character(startByte: byte) {
                    return .character(character)
                }
                return nil
            }
        }

        private func readEscapeKey() -> InputKey? {
            guard let second = readByte() else { return nil }
            if second == 0x5B {
                guard let third = readByte() else { return nil }
                switch third {
                case 0x41: return .up
                case 0x42: return .down
                case 0x43: return .right
                case 0x44: return .left
                case 0x48: return .home
                case 0x46: return .end
                case 0x33:
                    _ = readByte()
                    return .delete
                case 0x31, 0x37:
                    _ = readByte()
                    return .home
                case 0x34, 0x38:
                    _ = readByte()
                    return .end
                default:
                    return nil
                }
            }
            if second == 0x4F {
                guard let third = readByte() else { return nil }
                switch third {
                case 0x48: return .home
                case 0x46: return .end
                default: return nil
                }
            }
            return nil
        }

        private func readUTF8Character(startByte: UInt8) -> Character? {
            let expectedCount: Int
            switch startByte {
            case 0xC2...0xDF:
                expectedCount = 2
            case 0xE0...0xEF:
                expectedCount = 3
            case 0xF0...0xF4:
                expectedCount = 4
            default:
                return nil
            }

            var bytes: [UInt8] = [startByte]
            while bytes.count < expectedCount {
                guard let next = readByte() else { return nil }
                guard (next & 0b1100_0000) == 0b1000_0000 else { return nil }
                bytes.append(next)
            }

            guard let string = String(bytes: bytes, encoding: .utf8),
                  string.count == 1,
                  let character = string.first else {
                return nil
            }
            return character
        }

        private func render(buffer: [Character], cursor: Int) {
            let line = String(buffer)
            print("\r\(prompt)\(line)\u{001B}[K", terminator: "")
            let moveLeft = max(buffer.count - cursor, 0)
            if moveLeft > 0 {
                print("\u{001B}[\(moveLeft)D", terminator: "")
            }
            fflush(stdout)
        }

        private func beep() {
            print("\u{07}", terminator: "")
            fflush(stdout)
        }
    }

    private enum CommandLineTokenizeResult {
        case success([String])
        case failure(String)
    }

    private static func tokenizeCommandLine(_ input: String) -> CommandLineTokenizeResult {
        var tokens: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaping = false

        for char in input {
            if escaping {
                current.append(char)
                escaping = false
                continue
            }

            if char == "\\" {
                if inSingleQuote {
                    current.append(char)
                } else {
                    escaping = true
                }
                continue
            }

            if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }

            if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }

            if char.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(char)
        }

        if escaping {
            current.append("\\")
        }
        if inSingleQuote || inDoubleQuote {
            return .failure("Invalid command: missing closing quote.")
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return .success(tokens)
    }

    private static func clearTerminalScreen() {
        // ANSI clear screen + move cursor to home.
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        fflush(stdout)
    }

    private static func printTUIBanner() {
        let banner = #"""
 _                           _                     _      ____ _     ___ 
| |    __ _ _   _ _ __   ___| |__  _ __   _____  _| |_   / ___| |   |_ _|
| |   / _` | | | | '_ \ / __| '_ \| '_ \ / _ \ \/ / __| | |   | |    | | 
| |__| (_| | |_| | | | | (__| | | | | | |  __/>  <| |_  | |___| |___ | | 
|_____\__,_|\__,_|_| |_|\___|_| |_|_| |_|\___/_/\_\\__|  \____|_____|___|
"""#
        print(banner)
    }

    private static func appVersionString() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String

        switch (short, build) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty:
            return short == build ? short : "\(short) (\(build))"
        case let (short?, _):
            return short
        case let (_, build?):
            return build
        default:
            return "Unknown"
        }
    }

    private static func printCLIExamples() {
        print([
            "CLI examples:",
            "  launchnext --cli list",
            "  launchnext --cli snapshot",
            "  launchnext --cli history",
            "  launchnext --cli history --limit 20",
            "  launchnext --cli search --query \"safari\"",
            "  launchnext --cli create-folder --path \"/Applications/Mail.app\" --path \"/Applications/Notes.app\" --name \"Work\"",
            "  launchnext --cli move --source normal-app --path \"/Applications/Safari.app\" --to normal-index --index 12 --dry-run"
        ].joined(separator: "\n"))
    }

    private static func printTUIExamples() {
        print([
            "TUI examples:",
            "  list",
            "  snapshot",
            "  history",
            "  history --limit 20",
            "  search --query \"safari\"",
            "  create-folder --path \"/Applications/Mail.app\" --path \"/Applications/Notes.app\" --name \"Work\"",
            "  move --source normal-app --path \"/Applications/Safari.app\" --to normal-index --index 12 --dry-run"
        ].joined(separator: "\n"))
    }
}
