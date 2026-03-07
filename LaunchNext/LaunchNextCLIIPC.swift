import Foundation
import Dispatch
import Darwin

enum LaunchNextCLIIPCConfig {
    static let socketFileName = "cli.sock"

    static func socketPath() -> String? {
        let fm = FileManager.default
        guard let caches = try? fm.url(for: .cachesDirectory,
                                       in: .userDomainMask,
                                       appropriateFor: nil,
                                       create: true) else {
            return nil
        }
        let directory = caches.appendingPathComponent("LaunchNext", isDirectory: true)
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(socketFileName, isDirectory: false).path
    }
}

private struct LaunchNextCLIIPCRequest: Codable {
    let command: String
    let arguments: [String: String]
}

private struct LaunchNextCLIIPCResponse: Codable {
    let ok: Bool
    let output: String?
    let error: String?

    static func success(_ output: String) -> LaunchNextCLIIPCResponse {
        LaunchNextCLIIPCResponse(ok: true, output: output, error: nil)
    }

    static func failure(_ message: String) -> LaunchNextCLIIPCResponse {
        LaunchNextCLIIPCResponse(ok: false, output: nil, error: message)
    }
}

enum LaunchNextCLIIPCClient {
    static func execute(request: LaunchNextCLIRequest, socketPath: String) -> LaunchNextCLICommandResult {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return .failure("Failed to create CLI socket.")
        }
        defer { close(fd) }

        setSocketTimeout(fd: fd, seconds: 2)

        guard connectSocket(fd: fd, socketPath: socketPath) else {
            return .failure(
                "Please launch LaunchNext GUI first.\n" +
                "Run: open -a LaunchNext\n" +
                "Make sure \"Command line interface\" is ON in General settings."
            )
        }

        let payload = LaunchNextCLIIPCRequest(command: request.command, arguments: request.arguments)
        guard sendRequest(payload, fd: fd) else {
            return .failure("Failed to send CLI request.")
        }

        guard let response = receiveResponse(fd: fd) else {
            return .failure("Failed to receive CLI response.")
        }

        if response.ok {
            return .success(response.output ?? "")
        }
        return .failure(response.error ?? "CLI request failed.")
    }

    private static func setSocketTimeout(fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
    }

    private static func connectSocket(fd: Int32, socketPath: String) -> Bool {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(socketPath.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }

        let pathSize = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: CChar.self, repeating: 0)
            pathBytes.withUnsafeBytes { bytes in
                memcpy(rawBuffer.baseAddress, bytes.baseAddress, min(pathSize, bytes.count))
            }
        }

        let result = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }

    private static func sendRequest(_ request: LaunchNextCLIIPCRequest, fd: Int32) -> Bool {
        guard let data = try? JSONEncoder().encode(request) else { return false }
        var payload = data
        payload.append(0x0A)
        return writeAll(fd: fd, data: payload)
    }

    private static func receiveResponse(fd: Int32) -> LaunchNextCLIIPCResponse? {
        guard let lineData = readLine(fd: fd), !lineData.isEmpty else { return nil }
        return try? JSONDecoder().decode(LaunchNextCLIIPCResponse.self, from: lineData)
    }

    static func writeAll(fd: Int32, data: Data) -> Bool {
        var written = 0
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            while written < data.count {
                let result = write(fd, base.advanced(by: written), data.count - written)
                if result > 0 {
                    written += result
                    continue
                }
                if result == -1 && errno == EINTR {
                    continue
                }
                return false
            }
            return true
        }
    }

    static func readLine(fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 2048)
        let deadline = Date().addingTimeInterval(2.0)
        while data.count < 1_048_576 {
            let result = read(fd, &buffer, buffer.count)
            if result > 0 {
                data.append(buffer, count: result)
                if let newline = data.firstIndex(of: 0x0A) {
                    return data.subdata(in: 0..<newline)
                }
                continue
            }
            if result == 0 { break }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                if Date() >= deadline { return nil }
                usleep(10_000)
                continue
            }
            return nil
        }
        return data.isEmpty ? nil : data
    }
}

final class LaunchNextCLIIPCServer {
    typealias CommandHandler = (String, [String: String]) -> LaunchNextCLICommandResult

    private let socketPath: String
    private let commandHandler: CommandHandler
    private let queue = DispatchQueue(label: "io.roversx.launchnext.cli.ipc")

    private var listeningFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    init(socketPath: String, commandHandler: @escaping CommandHandler) {
        self.socketPath = socketPath
        self.commandHandler = commandHandler
    }

    func start() throws {
        stop()

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "LaunchNextCLIIPCServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create server socket."])
        }

        if !bindAndListen(fd: fd) {
            close(fd)
            throw NSError(domain: "LaunchNextCLIIPCServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind CLI socket."])
        }

        setNonBlocking(fd: fd)
        listeningFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingConnections()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.listeningFD >= 0 {
                close(self.listeningFD)
                self.listeningFD = -1
            }
        }
        acceptSource = source
        source.resume()
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil

        if listeningFD >= 0 {
            close(listeningFD)
            listeningFD = -1
        }

        unlink(socketPath)
    }

    deinit {
        stop()
    }

    private func bindAndListen(fd: Int32) -> Bool {
        unlink(socketPath)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(socketPath.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }

        let pathSize = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: CChar.self, repeating: 0)
            pathBytes.withUnsafeBytes { bytes in
                memcpy(rawBuffer.baseAddress, bytes.baseAddress, min(pathSize, bytes.count))
            }
        }

        let bindResult = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { return false }
        return listen(fd, SOMAXCONN) == 0
    }

    private func setNonBlocking(fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
    }

    private func acceptPendingConnections() {
        while true {
            let clientFD = accept(listeningFD, nil, nil)
            if clientFD < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                    break
                }
                break
            }
            setBlocking(fd: clientFD)

            queue.async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ clientFD: Int32) {
        defer { close(clientFD) }

        guard let line = LaunchNextCLIIPCClient.readLine(fd: clientFD),
              let request = try? JSONDecoder().decode(LaunchNextCLIIPCRequest.self, from: line) else {
            let response = LaunchNextCLIIPCResponse.failure("Invalid CLI request.")
            _ = sendResponse(response, to: clientFD)
            return
        }

        let result = commandHandler(request.command, request.arguments)
        let response: LaunchNextCLIIPCResponse
        switch result {
        case .success(let output):
            response = .success(output)
        case .failure(let message):
            response = .failure(message)
        }
        _ = sendResponse(response, to: clientFD)
    }

    private func sendResponse(_ response: LaunchNextCLIIPCResponse, to fd: Int32) -> Bool {
        guard let data = try? JSONEncoder().encode(response) else { return false }
        var payload = data
        payload.append(0x0A)
        return LaunchNextCLIIPCClient.writeAll(fd: fd, data: payload)
    }

    private func setBlocking(fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else { return }
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
    }
}
