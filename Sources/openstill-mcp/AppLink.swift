import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct LinkError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The local connection to OpenStill: newline-delimited JSON over a Unix socket that only this Mac user can open.
/// OpenStill listens only while Settings → AI Assistant → "Allow AI assistants to edit" is on.
class AppLink {
    /// Must match OpenStill's `Assistant.protocolVersion`.
    static let protocolVersion = 1
    static let bundleID = "org.openstill.viewer"

    var onMessage: (([String: Any]) -> Void)?
    var onDisconnect: (() -> Void)?

    static var folder: URL {
        if let path = ProcessInfo.processInfo.environment["OPENSTILL_ASSISTANT_DIR"], !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenStill", isDirectory: true)
    }
    static var socketPath: String { folder.appendingPathComponent("assistant.sock").path }

    private let connectLock = NSLock()
    private let writeLock = NSLock()
    private var fd: Int32 = -1
    private let welcomeLock = NSLock()
    /// While connecting: the signal and OpenStill's first answer.
    private var welcome: (DispatchSemaphore, [String: Any]?)?

    var isConnected: Bool { connectLock.lock(); defer { connectLock.unlock() }; return fd >= 0 }

    /// Connects and says hello. When `launch` is true and OpenStill isn't answering, opens it in the background and waits for it.
    func connect(hello: [String: Any], launch: Bool) throws {
        connectLock.lock(); defer { connectLock.unlock() }
        guard fd < 0 else { return }
        var socket = Self.open(Self.socketPath)
        if socket < 0 && launch {
            Self.launchOpenStill()
            let deadline = Date().addingTimeInterval(20)
            while socket < 0 && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
                socket = Self.open(Self.socketPath)
            }
        }
        guard socket >= 0 else {
            throw LinkError(message: "OpenStill isn't accepting AI requests. Open OpenStill, then turn on Settings → AI Assistant → “Allow AI assistants to edit”.")
        }
        fd = socket
        let waiter = DispatchSemaphore(value: 0)
        welcomeLock.lock(); welcome = (waiter, nil); welcomeLock.unlock()
        let reader = Thread { [weak self] in self?.read(socket) }
        reader.name = "OpenStill link"
        reader.start()
        do { try write(hello, to: socket) } catch { close(socket); fd = -1; throw error }
        let answered = waiter.wait(timeout: .now() + 10) == .success
        welcomeLock.lock(); let answer = welcome?.1; welcome = nil; welcomeLock.unlock()
        guard answered, let answer else {
            fd = -1; Darwin.shutdown(socket, SHUT_RDWR)
            throw LinkError(message: "OpenStill didn't answer. Make sure it's up to date.")
        }
        if let error = answer["error"] as? String { fd = -1; Darwin.shutdown(socket, SHUT_RDWR); throw LinkError(message: error) }
    }

    func send(_ message: [String: Any]) throws {
        connectLock.lock(); let socket = fd; connectLock.unlock()
        guard socket >= 0 else { throw LinkError(message: "Not connected to OpenStill.") }
        try write(message, to: socket)
    }

    // MARK: Socket
    private func write(_ message: [String: Any], to socket: Int32) throws {
        var data = try JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes])
        data.append(0x0A)
        writeLock.lock(); defer { writeLock.unlock() }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(socket, raw.baseAddress! + offset, raw.count - offset)
                if written > 0 { offset += written; continue }
                if written < 0 && errno == EINTR { continue }
                throw LinkError(message: "Lost the connection to OpenStill.")
            }
        }
    }

    private func read(_ socket: Int32) {
        var framing = LineFraming()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        loop: while true {
            let count = Darwin.read(socket, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { break }
            guard let lines = try? framing.append(Data(buffer[0..<count])) else { break }
            for line in lines {
                guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
                welcomeLock.lock()
                let waiting = welcome
                let isAnswer = waiting != nil && waiting!.1 == nil && (message["type"] as? String == "welcome" || message["error"] != nil)
                if isAnswer { welcome = (waiting!.0, message) }
                welcomeLock.unlock()
                if isAnswer {
                    waiting!.0.signal()
                    if message["error"] != nil { break loop }
                    continue
                }
                onMessage?(message)
            }
        }
        connectLock.lock()
        if fd == socket { fd = -1 }
        connectLock.unlock()
        close(socket)
        onDisconnect?()
    }

    static func open(_ path: String) -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return -1 }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: bytes); raw[bytes.count] = 0 }
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { return -1 }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { close(socket); return -1 }
        var one: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return socket
    }

    /// Opens OpenStill without bringing it to the front.
    static func launchOpenStill() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-g", "-b", bundleID, "--args", "--assistant"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}

/// Splits a byte stream into lines, refusing runaway lines.
struct LineFraming {
    static let maximumLine = 48_000_000
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let end = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<end])
            buffer.removeSubrange(buffer.startIndex...end)
            if !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D }) { lines.append(line) }
        }
        if buffer.count > Self.maximumLine { buffer.removeAll(); throw LinkError(message: "A message was too large.") }
        return lines
    }
}
