import Foundation
import XCTest
@testable import openstill_mcp

/// Stands in for OpenStill: records what the MCP sends and answers like the app would.
final class FakeApp: AppLink {
    var sent: [[String: Any]] = []
    var hellos: [[String: Any]] = []
    var connectError: String?
    var answer: (([String: Any]) -> [String: Any]?)?
    override func connect(hello: [String: Any], launch: Bool) throws {
        if let connectError { throw LinkError(message: connectError) }
        hellos.append(hello)
    }
    override func send(_ message: [String: Any]) throws {
        sent.append(message)
        if let reply = answer?(message) { onMessage?(reply) }
    }
}

final class ServerTests: XCTestCase {
    private func make() -> (Server, FakeApp, () -> [[String: Any]]) {
        let app = FakeApp()
        let lock = NSLock()
        var out: [[String: Any]] = []
        let server = Server(app: app) { message in lock.lock(); out.append(message); lock.unlock() }
        return (server, app, { lock.lock(); defer { lock.unlock() }; return out })
    }
    private func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    }

    func testInitializeAgreesOnAVersionAndNotesSampling() {
        let (server, _, out) = make()
        server.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                       "params": ["protocolVersion": "2024-11-05", "capabilities": ["sampling": [:]], "clientInfo": ["name": "Claude", "version": "1.2"]]])
        let result = out()[0]["result"] as! [String: Any]
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "openstill")
        let client = server.hello["client"] as! [String: Any]
        XCTAssertEqual(client["name"] as? String, "Claude")
        XCTAssertEqual(client["supportsSampling"] as? Bool, true)
        XCTAssertEqual(server.hello["version"] as? Int, AppLink.protocolVersion)

        server.handle(["jsonrpc": "2.0", "id": 2, "method": "initialize", "params": ["protocolVersion": "1999-01-01"]])
        XCTAssertEqual((out()[1]["result"] as! [String: Any])["protocolVersion"] as? String, Server.protocolVersions[0])
    }

    func testEveryToolHasAValidSchema() throws {
        let (server, _, out) = make()
        server.handle(["jsonrpc": "2.0", "id": 1, "method": "tools/list"])
        let tools = (out()[0]["result"] as! [String: Any])["tools"] as! [[String: Any]]
        XCTAssertEqual(tools.count, Tools.all.count)
        XCTAssertEqual(Set(tools.map { $0["name"] as! String }).count, tools.count, "tool names are unique")
        for tool in tools {
            let schema = tool["inputSchema"] as! [String: Any]
            XCTAssertEqual(schema["type"] as? String, "object")
            XCTAssertFalse((tool["description"] as! String).isEmpty)
            XCTAssertTrue(JSONSerialization.isValidJSONObject(tool))
        }
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: tools))
    }

    func testMaskLayersCanBeSeenChangedAndRemoved() {
        let names = Set(Tools.all.map(\.name))
        for tool in ["add_mask_layer", "list_mask_layers", "preview_mask", "update_mask_layer", "delete_mask_layer"] { XCTAssertTrue(names.contains(tool), tool) }
        let update = Tools.all.first { $0.name == "update_mask_layer" }!
        XCTAssertEqual(update.schema["required"] as? [String], ["layer_id"])
        XCTAssertTrue(Tools.all.first { $0.name == "preview_mask" }!.readOnly)
        let preview = (Tools.all.first { $0.name == "preview" }!.schema["properties"] as! [String: Any])
        XCTAssertNotNil(preview["compare"])
        // A mask view comes back as the image plus its facts.
        let content = Server.content(["mime": "image/jpeg", "data": "AAAA", "selection": ["coverage": 0.4]])
        XCTAssertEqual(content.first?["type"] as? String, "image")
        XCTAssertTrue((content.last?["text"] as? String ?? "").contains("coverage"))
    }

    func testFullEditingToolsAreOffered() {
        let names = Set(Tools.all.map(\.name))
        for tool in ["edit_reference", "get_edits", "edit", "run_command", "copy_edits", "list_presets", "list_skies"] { XCTAssertTrue(names.contains(tool), tool) }
        XCTAssertEqual(Tools.all.first { $0.name == "edit" }!.schema["required"] as? [String], ["patch"])
        XCTAssertEqual(Tools.all.first { $0.name == "copy_edits" }!.schema["required"] as? [String], ["to_photo_ids"])
        XCTAssertEqual(Set(Tools.commands).count, Tools.commands.count)
        XCTAssertTrue(Tools.all.first { $0.name == "get_edits" }!.readOnly)
    }

    func testToolCallsAreForwardedAndAnswered() {
        let (server, app, out) = make()
        app.answer = { message in ["type": "response", "id": message["id"]!, "result": ["exposure": 0.3]] }
        server.handle(["jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": "set_adjustments", "arguments": ["values": ["exposure": 0.3]]]])
        wait { !out().isEmpty }
        XCTAssertEqual(app.sent.first?["tool"] as? String, "set_adjustments")
        XCTAssertEqual(app.sent.first?["type"] as? String, "request")
        let reply = out()[0]
        XCTAssertEqual(reply["id"] as? Int, 7)
        let result = reply["result"] as! [String: Any]
        XCTAssertEqual(result["isError"] as? Bool, false)
        let text = ((result["content"] as! [[String: Any]])[0]["text"] as! String)
        XCTAssertTrue(text.contains("\"exposure\""), text)
    }

    func testErrorsComeBackAsToolErrors() {
        let (server, app, out) = make()
        app.connectError = "OpenStill isn't accepting AI requests."
        server.handle(["jsonrpc": "2.0", "id": "a", "method": "tools/call", "params": ["name": "status"]])
        wait { !out().isEmpty }
        let result = out()[0]["result"] as! [String: Any]
        XCTAssertEqual(result["isError"] as? Bool, true)

        app.connectError = nil
        app.answer = { message in ["type": "response", "id": message["id"]!, "error": "No photo is open."] }
        server.handle(["jsonrpc": "2.0", "id": "b", "method": "tools/call", "params": ["name": "get_photo"]])
        wait { out().count == 2 }
        let second = out()[1]["result"] as! [String: Any]
        XCTAssertEqual(second["isError"] as? Bool, true)
        XCTAssertEqual(((second["content"] as! [[String: Any]])[0]["text"] as? String), "No photo is open.")

        server.handle(["jsonrpc": "2.0", "id": "c", "method": "tools/call", "params": ["name": "delete_everything"]])
        XCTAssertNotNil(out()[2]["error"], "unknown tools are refused without reaching OpenStill")
        XCTAssertEqual(app.sent.count, 1)
    }

    func testPreviewsBecomeImages() {
        let content = Server.content(["mime": "image/jpeg", "data": "AAAA", "width": 1024])
        XCTAssertEqual(content[0]["type"] as? String, "image")
        XCTAssertEqual(content[0]["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(content[1]["text"] as? String, "{\"width\":1024}")
    }

    func testSamplingIsRelayedBothWays() {
        let (server, app, out) = make()
        server.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["capabilities": ["sampling": [:]]]])
        server.fromApp(["type": "sample", "id": "logo-1", "arguments": ["maxTokens": 900, "messages": []]])
        let request = out()[1]
        XCTAssertEqual(request["method"] as? String, "sampling/createMessage")
        XCTAssertEqual((request["params"] as? [String: Any])?["maxTokens"] as? Int, 900)
        server.handle(["jsonrpc": "2.0", "id": request["id"]!, "result": ["role": "assistant", "content": ["type": "text", "text": "{}"]]])
        XCTAssertEqual(app.sent.last?["type"] as? String, "sampleResult")
        XCTAssertEqual(app.sent.last?["id"] as? String, "logo-1")
        XCTAssertNotNil(app.sent.last?["result"])
    }

    func testSamplingIsRefusedWhenTheClientCantAnswer() {
        let (server, app, out) = make()
        server.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:]])
        server.fromApp(["type": "sample", "id": "logo-2", "arguments": [:]])
        XCTAssertEqual(out().count, 1, "nothing is sent to a client without sampling")
        XCTAssertEqual(app.sent.last?["id"] as? String, "logo-2")
        XCTAssertNotNil(app.sent.last?["error"])
    }

    func testPrompts() {
        let (server, _, out) = make()
        server.handle(["jsonrpc": "2.0", "id": 1, "method": "prompts/list"])
        XCTAssertEqual(((out()[0]["result"] as! [String: Any])["prompts"] as! [Any]).count, Prompts.all.count)
        server.handle(["jsonrpc": "2.0", "id": 2, "method": "prompts/get", "params": ["name": "find_luts", "arguments": ["style": "teal and orange"]]])
        let messages = (out()[1]["result"] as! [String: Any])["messages"] as! [[String: Any]]
        XCTAssertTrue(((messages[0]["content"] as! [String: Any])["text"] as! String).contains("teal and orange"))
        server.handle(["jsonrpc": "2.0", "id": 3, "method": "prompts/get", "params": ["name": "nope"]])
        XCTAssertNotNil(out()[2]["error"])
    }

    func testUnknownMethodsAndBadInput() {
        let (server, _, out) = make()
        server.handle(["jsonrpc": "2.0", "id": 1, "method": "something/else"])
        XCTAssertEqual((out()[0]["error"] as? [String: Any])?["code"] as? Int, -32601)
        server.handle(["jsonrpc": "2.0", "method": "notifications/cancelled"])
        XCTAssertEqual(out().count, 1, "notifications get no reply")
        server.handle(line: Data("not json".utf8))
        XCTAssertEqual((out()[1]["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    func testFramingSplitsLinesAndRefusesRunaways() throws {
        var framing = LineFraming()
        XCTAssertEqual(try framing.append(Data("{\"a\":1}\n{\"b\"".utf8)).count, 1)
        XCTAssertEqual(try framing.append(Data(":2}\n\n".utf8)).map { String(data: $0, encoding: .utf8)! }, ["{\"b\":2}"])
        XCTAssertThrowsError(try framing.append(Data(count: LineFraming.maximumLine + 1)))
    }

    func testTheAppGoingAwayAnswersWaitingCalls() {
        let (server, app, out) = make()
        server.handle(["jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": ["name": "status"]])
        wait { !app.sent.isEmpty }
        app.onDisconnect?()
        wait { !out().isEmpty }
        XCTAssertEqual((out()[0]["result"] as? [String: Any])?["isError"] as? Bool, true)
    }
}
