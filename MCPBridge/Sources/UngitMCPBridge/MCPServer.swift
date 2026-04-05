import Foundation

final class MCPDiagnosticsLogger {
    static let shared = MCPDiagnosticsLogger()

    private let queue = DispatchQueue(label: "ungit.mcp.logger")
    private let maxBytes: UInt64 = 1_000_000
    private let logURL: URL

    private init() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let logsDir = home.appendingPathComponent("Library/Logs/UNGIT", isDirectory: true)
        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logURL = logsDir.appendingPathComponent("mcp-server.log", isDirectory: false)
    }

    func log(_ message: String) {
        queue.sync {
            self.rotateIfNeeded()
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: self.logURL.path) {
                guard let handle = try? FileHandle(forWritingTo: self.logURL) else { return }
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    // Swallow log write failures to avoid affecting server behavior.
                }
            } else {
                try? data.write(to: self.logURL, options: .atomic)
            }
        }
    }

    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: logURL.path),
              let size = attrs[.size] as? NSNumber,
              size.uint64Value > maxBytes else {
            return
        }

        let rotated = logURL.deletingLastPathComponent().appendingPathComponent("mcp-server.log.1")
        try? fm.removeItem(at: rotated)
        try? fm.moveItem(at: logURL, to: rotated)
    }
}

public struct JSONRPCRequest: Codable {
    public var jsonrpc: String
    public var id: JSONValue?
    public var method: String
    public var params: JSONValue?
}

public struct JSONRPCResponse: Codable {
    public var jsonrpc: String = "2.0"
    public var id: JSONValue?
    public var result: JSONValue?
    public var error: JSONRPCError?
}

public struct JSONRPCError: Codable {
    public var code: Int
    public var message: String
}

public final class MCPServer {
    private enum MessageFraming: String {
        case contentLength = "content-length"
        case ndjson = "ndjson"
    }

    private let router = UngitToolRouter()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = MCPDiagnosticsLogger.shared

    public init() {}

    public func run() {
        logger.log("MCP server started (pid: \(ProcessInfo.processInfo.processIdentifier)).")
        while let message = readMessage() {
            let requestData = message.data
            guard !requestData.isEmpty else { continue }
            guard let request = try? decoder.decode(JSONRPCRequest.self, from: requestData) else {
                let preview = String(data: requestData.prefix(300), encoding: .utf8) ?? "<non-utf8>"
                logger.log("Failed to decode JSON-RPC request. Payload preview: \(preview)")
                continue
            }

            if request.method == "notifications/initialized" {
                logger.log("Received notifications/initialized.")
                continue
            }

            logger.log("Received request method: \(request.method) [framing: \(message.framing.rawValue)]")

            let response = handle(request: request)
            if let response, let data = try? encoder.encode(response) {
                writeMessage(data, framing: message.framing)
            }
        }
        logger.log("MCP server input closed; exiting run loop.")
    }

    private func handle(request: JSONRPCRequest) -> JSONRPCResponse? {
        switch request.method {
        case "initialize":
            logger.log("Handling initialize.")
            return JSONRPCResponse(
                id: request.id,
                result: .object([
                    "protocolVersion": .string("2024-11-05"),
                    "capabilities": .object([
                        "tools": .object([:]),
                        "resources": .object([:])
                    ]),
                    "serverInfo": .object([
                        "name": .string("ungit-mcp"),
                        "version": .string("0.1.0")
                    ])
                ])
            )
        case "tools/list":
            logger.log("Handling tools/list.")
            let defs = router.toolDefinitions()
            guard let defsJSON = try? encodeToJSONValue(defs) else {
                logger.log("Failed to encode tool definitions.")
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32603, message: "Failed to encode tools"))
            }
            return JSONRPCResponse(id: request.id, result: .object(["tools": defsJSON]))
        case "resources/list":
            logger.log("Handling resources/list.")
            return JSONRPCResponse(id: request.id, result: .object([
                "resources": .array([
                    .object([
                        "uri": .string("ungit://status"),
                        "name": .string("UNGIT MCP Status"),
                        "mimeType": .string("application/json"),
                        "description": .string("Live MCP attachment and tool availability status.")
                    ])
                ])
            ]))
        case "resources/templates/list":
            logger.log("Handling resources/templates/list.")
            return JSONRPCResponse(id: request.id, result: .object([
                "resourceTemplates": .array([])
            ]))
        case "resources/read":
            logger.log("Handling resources/read.")
            guard let params = request.params?.objectValue,
                  let uri = params["uri"]?.stringValue else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32602, message: "Missing uri"))
            }
            guard uri == "ungit://status" else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32602, message: "Unknown resource uri"))
            }

            let defs = router.toolDefinitions()
            let toolNames = defs.map(\.name).sorted()
            let statusPayload: [String: Any] = [
                "ok": true,
                "server": "ungit-mcp",
                "version": "0.1.0",
                "tool_count": toolNames.count,
                "tools": toolNames
            ]

            guard let statusData = try? JSONSerialization.data(withJSONObject: statusPayload, options: [.prettyPrinted, .sortedKeys]),
                  let statusText = String(data: statusData, encoding: .utf8) else {
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32603, message: "Failed to encode resource"))
            }

            return JSONRPCResponse(id: request.id, result: .object([
                "contents": .array([
                    .object([
                        "uri": .string("ungit://status"),
                        "mimeType": .string("application/json"),
                        "text": .string(statusText)
                    ])
                ])
            ]))
        case "tools/call":
            guard let params = request.params?.objectValue else {
                logger.log("tools/call missing params.")
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32602, message: "Missing params"))
            }
            guard let name = params["name"]?.stringValue else {
                logger.log("tools/call missing tool name.")
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32602, message: "Missing tool name"))
            }
            logger.log("Handling tools/call for tool: \(name)")
            let args = params["arguments"]?.objectValue ?? [:]
            let envelope = router.execute(tool: name, arguments: args)
            guard let envelopeJSON = try? encodeToJSONValue(envelope) else {
                logger.log("Failed to encode tool result for tool: \(name)")
                return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32603, message: "Failed to encode result"))
            }

            let text = (try? prettyJSONString(from: envelopeJSON)) ?? "{}"
            return JSONRPCResponse(id: request.id, result: .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(text)
                    ])
                ]),
                "structuredContent": envelopeJSON,
                "isError": .bool(!envelope.ok)
            ]))
        default:
            logger.log("Method not found: \(request.method)")
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32601, message: "Method not found"))
        }
    }

    private func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return JSONValue.fromAny(object)
    }

    private func prettyJSONString(from value: JSONValue) throws -> String {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(data: pretty, encoding: .utf8) ?? "{}"
    }

    private func readMessage() -> (data: Data, framing: MessageFraming)? {
        let stdin = FileHandle.standardInput
        while let rawLine = readLine(from: stdin) {
            guard let firstLine = String(data: rawLine, encoding: .utf8) else {
                logger.log("Failed to decode incoming line as UTF-8.")
                continue
            }
            let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            if let initialLength = parseContentLength(from: trimmed) {
                var contentLength = initialLength
                logger.log("Detected content-length framing.")

                while let headerLineData = readLine(from: stdin) {
                    guard let headerLine = String(data: headerLineData, encoding: .utf8) else {
                        logger.log("Failed to decode header line as UTF-8.")
                        continue
                    }
                    let normalized = headerLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if normalized.isEmpty {
                        break
                    }
                    if let overrideLength = parseContentLength(from: normalized) {
                        contentLength = overrideLength
                    }
                }

                guard contentLength > 0 else {
                    logger.log("Read message with missing/invalid Content-Length.")
                    continue
                }

                var body = Data()
                while body.count < contentLength {
                    let chunk = stdin.readData(ofLength: contentLength - body.count)
                    if chunk.isEmpty { break }
                    body.append(chunk)
                }

                if body.count != contentLength {
                    logger.log("Content-Length mismatch. Expected \(contentLength), got \(body.count).")
                    continue
                }
                return (body, .contentLength)
            }

            logger.log("Detected ndjson framing.")
            return (Data(trimmed.utf8), .ndjson)
        }
        return nil
    }

    private func parseContentLength(from line: String) -> Int? {
        let lower = line.lowercased()
        guard lower.hasPrefix("content-length:"),
              let raw = line.split(separator: ":", maxSplits: 1).last else {
            return nil
        }
        return Int(String(raw).trimmingCharacters(in: .whitespaces))
    }

    private func readLine(from input: FileHandle) -> Data? {
        var buffer = Data()
        while true {
            let byte = input.readData(ofLength: 1)
            if byte.isEmpty {
                return buffer.isEmpty ? nil : buffer
            }
            if byte == Data([10]) { // \n
                if buffer.last == 13 { // trim trailing \r
                    buffer.removeLast()
                }
                return buffer
            }
            buffer.append(byte)
        }
    }

    private func writeMessage(_ data: Data, framing: MessageFraming) {
        let stdout = FileHandle.standardOutput
        logger.log("Writing response (bytes: \(data.count), framing: \(framing.rawValue)).")
        switch framing {
        case .contentLength:
            let header = "Content-Length: \(data.count)\r\n\r\n"
            if let headerData = header.data(using: .utf8) {
                stdout.write(headerData)
            }
            stdout.write(data)
        case .ndjson:
            stdout.write(data)
            stdout.write(Data([10]))
        }
    }
}
