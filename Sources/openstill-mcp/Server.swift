import Foundation

/// The MCP side: JSON-RPC 2.0 over stdio, one message per line.
/// Tool calls are forwarded to OpenStill and answered when OpenStill replies, so the AI app can keep talking meanwhile.
/// OpenStill can also ask the AI app to answer something (MCP sampling), for example to design logos.
final class Server {
    static let name = "openstill"
    static let version = "1.2.0"
    static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    /// Writes one JSON-RPC message to the AI app.
    let output: ([String: Any]) -> Void
    /// The connection to OpenStill (replaceable in tests).
    let app: AppLink
    private let lock = NSLock()
    private var clientName = "AI assistant", clientVersion = "", clientSamples = false
    /// Tool calls waiting for OpenStill, by our id → the AI app's JSON-RPC id.
    private var waiting: [String: Any] = [:]
    /// Sampling requests sent to the AI app, by JSON-RPC id → OpenStill's id.
    private var sampling: [String: String] = [:]
    private var nextID = 0

    init(app: AppLink, output: @escaping ([String: Any]) -> Void) {
        self.app = app; self.output = output
        app.onMessage = { [weak self] message in self?.fromApp(message) }
        app.onDisconnect = { [weak self] in self?.appWentAway() }
    }

    var hello: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["type": "hello", "version": AppLink.protocolVersion,
                "client": ["name": clientName, "version": clientVersion, "supportsSampling": clientSamples]]
    }

    // MARK: From the AI app
    func handle(line: Data) {
        guard !line.isEmpty else { return }
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            output(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]]); return
        }
        handle(message)
    }

    func handle(_ message: [String: Any]) {
        let id = message["id"]
        guard let method = message["method"] as? String else {
            if let id { fromClientResponse(id: id, message) }
            return
        }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let info = params["clientInfo"] as? [String: Any] ?? [:]
            let capabilities = params["capabilities"] as? [String: Any] ?? [:]
            lock.lock()
            clientName = info["name"] as? String ?? "AI assistant"
            clientVersion = info["version"] as? String ?? ""
            clientSamples = capabilities["sampling"] != nil
            lock.unlock()
            let requested = params["protocolVersion"] as? String ?? ""
            let version = Self.protocolVersions.contains(requested) ? requested : Self.protocolVersions[0]
            reply(id, ["protocolVersion": version,
                       "capabilities": ["tools": ["listChanged": false], "prompts": ["listChanged": false]],
                       "serverInfo": ["name": Self.name, "title": "OpenStill", "version": Self.version],
                       "instructions": "Edits photos in OpenStill, a photo editor on this Mac, with everything its Develop panel can do. Call status or list_photos first and preview to look. For anything beyond the basic sliders (curves, HSL, color grading, glow, grain, point color, detail, lens, transform, calibration, retouch, masks, lens blur…) call edit_reference once, read get_edits, and change it with edit (a JSON merge patch). Buttons (auto tone, Upright, AI noise removal, erase, skies, snapshots) are run_command; copy settings between photos with copy_edits. Every change is one undo step; check with preview compare: true."])
        case "notifications/initialized":
            // Connect early when OpenStill is already running, so it knows this AI app can answer its requests.
            let app = self.app, hello = self.hello
            DispatchQueue.global().async { try? app.connect(hello: hello, launch: false) }
        case "ping":
            reply(id, [:])
        case "tools/list":
            reply(id, ["tools": Tools.list])
        case "tools/call":
            call(id, params)
        case "prompts/list":
            reply(id, ["prompts": Prompts.list])
        case "prompts/get":
            let name = params["name"] as? String ?? ""
            let arguments = (params["arguments"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            guard let text = Prompts.text(name, arguments) else { fail(id, -32602, "Unknown prompt “\(name)”."); return }
            reply(id, ["description": Prompts.all.first { $0.name == name }?.description ?? "",
                       "messages": [["role": "user", "content": ["type": "text", "text": text]]]])
        case "resources/list": reply(id, ["resources": []])
        case "resources/templates/list": reply(id, ["resourceTemplates": []])
        default:
            if method.hasPrefix("notifications/") { return }
            fail(id, -32601, "Method not found: \(method)")
        }
    }

    private func call(_ id: Any?, _ params: [String: Any]) {
        let tool = params["name"] as? String ?? ""
        guard Tools.exists(tool) else { fail(id, -32602, "Unknown tool “\(tool)”."); return }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        lock.lock(); nextID += 1; let key = "t\(nextID)"; waiting[key] = id ?? NSNull(); lock.unlock()
        DispatchQueue.global().async { [self] in
            do {
                try app.connect(hello: hello, launch: true)
                try app.send(["type": "request", "id": key, "tool": tool, "arguments": arguments])
            } catch {
                finish(key, error: error.localizedDescription)
            }
        }
    }

    // MARK: From OpenStill
    func fromApp(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "response":
            guard let key = message["id"] as? String else { return }
            if let error = message["error"] as? String { finish(key, error: error) } else { finish(key, result: message["result"] ?? NSNull()) }
        case "sample":
            guard let appID = message["id"] as? String else { return }
            lock.lock()
            let supported = clientSamples
            nextID += 1; let rpcID = "s\(nextID)"
            if supported { sampling[rpcID] = appID }
            lock.unlock()
            guard supported else { try? app.send(["type": "sampleResult", "id": appID, "error": "This AI app can't answer requests from OpenStill."]); return }
            output(["jsonrpc": "2.0", "id": rpcID, "method": "sampling/createMessage", "params": message["arguments"] ?? [:]])
        default:
            break // welcome and anything newer are ignored
        }
    }

    private func fromClientResponse(id: Any, _ message: [String: Any]) {
        guard let rpcID = id as? String else { return }
        lock.lock(); let appID = sampling.removeValue(forKey: rpcID); lock.unlock()
        guard let appID else { return }
        if let error = message["error"] as? [String: Any] {
            try? app.send(["type": "sampleResult", "id": appID, "error": error["message"] as? String ?? "The AI app declined."])
        } else {
            try? app.send(["type": "sampleResult", "id": appID, "result": message["result"] ?? NSNull()])
        }
    }

    private func appWentAway() {
        lock.lock(); let keys = Array(waiting.keys); sampling.removeAll(); lock.unlock()
        for key in keys { finish(key, error: "OpenStill closed before answering.") }
    }

    // MARK: Replies
    /// Turns OpenStill's answer into tool content: images as images, everything else as JSON text.
    static func content(_ result: Any) -> [[String: Any]] {
        if let object = result as? [String: Any], let mime = object["mime"] as? String, let data = object["data"] as? String, mime.hasPrefix("image/") {
            var rest = object; rest["data"] = nil; rest["mime"] = nil
            var content: [[String: Any]] = [["type": "image", "mimeType": mime, "data": data]]
            if !rest.isEmpty { content.append(["type": "text", "text": json(rest)]) }
            return content
        }
        return [["type": "text", "text": json(result)]]
    }
    static func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return String(describing: value) }
        return String(text.dropFirst().dropLast())
    }

    private func finish(_ key: String, result: Any? = nil, error: String? = nil) {
        lock.lock(); let id = waiting.removeValue(forKey: key); lock.unlock()
        guard let id else { return }
        if let error { reply(id, ["content": [["type": "text", "text": error]], "isError": true]) }
        else { reply(id, ["content": Self.content(result ?? NSNull()), "isError": false]) }
    }
    private func reply(_ id: Any?, _ result: [String: Any]) {
        guard let id else { return }
        output(["jsonrpc": "2.0", "id": id, "result": result])
    }
    private func fail(_ id: Any?, _ code: Int, _ message: String) {
        guard let id else { return }
        output(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }
}
