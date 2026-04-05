import Foundation

public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    public static func fromAny(_ value: Any) -> JSONValue {
        switch value {
        case let v as String:
            return .string(v)
        case let v as NSNumber:
            if CFGetTypeID(v) == CFBooleanGetTypeID() {
                return .bool(v.boolValue)
            }
            return .number(v.doubleValue)
        case let v as Bool:
            return .bool(v)
        case let v as [Any]:
            return .array(v.map { JSONValue.fromAny($0) })
        case let v as [String: Any]:
            return .object(v.mapValues { JSONValue.fromAny($0) })
        default:
            return .null
        }
    }
}

public struct ToolEnvelope: Codable {
    public var ok: Bool
    public var tool: String
    public var stepFailed: String?
    public var reason: String?
    public var data: JSONValue?

    enum CodingKeys: String, CodingKey {
        case ok
        case tool
        case stepFailed = "step_failed"
        case reason
        case data
    }

    public static func success(tool: String, data: JSONValue) -> ToolEnvelope {
        ToolEnvelope(ok: true, tool: tool, stepFailed: nil, reason: nil, data: data)
    }

    public static func failure(tool: String, step: String, reason: String) -> ToolEnvelope {
        ToolEnvelope(ok: false, tool: tool, stepFailed: step, reason: reason, data: nil)
    }
}

public struct MCPToolDefinition: Codable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "inputSchema"
    }
}
