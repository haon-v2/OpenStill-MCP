import Foundation

// OpenStill MCP: lets an AI app (Claude Desktop, Claude Code or any MCP client) edit photos in OpenStill.
// It speaks MCP over stdin/stdout and forwards each tool call to the OpenStill app on this Mac.

if CommandLine.arguments.contains("--version") {
    print("openstill-mcp \(Server.version)")
    exit(0)
}

signal(SIGPIPE, SIG_IGN)
let outputLock = NSLock()
let server = Server(app: AppLink()) { message in
    guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
    data.append(0x0A)
    outputLock.lock(); defer { outputLock.unlock() }
    FileHandle.standardOutput.write(data)
}

var framing = LineFraming()
while true {
    let chunk = FileHandle.standardInput.availableData
    if chunk.isEmpty { break } // the AI app closed the connection
    guard let lines = try? framing.append(chunk) else { continue }
    for line in lines { server.handle(line: line) }
}
