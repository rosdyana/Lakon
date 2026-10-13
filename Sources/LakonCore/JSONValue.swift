import Foundation

/// Untyped JSON value. Event command parameters in MZ are heterogeneous arrays
/// (`{"code":101,"indent":0,"parameters":["Actor1",0,0,2,""]}`), so they are kept as-is.
public enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public var int: Int {
        switch self {
        case .number(let n): return Int(n)
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return Int(s) ?? 0
        default: return 0
        }
    }
    public var string: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.rounded() == n ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return ""
        }
    }
    public var bool: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        default: return false
        }
    }
    public var array: [JSONValue] { if case .array(let a) = self { return a } else { return [] } }
}

extension JSONValue: ExpressibleByIntegerLiteral, ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public static func int(_ v: Int) -> JSONValue { .number(Double(v)) }
}

extension Array where Element == JSONValue {
    /// Safe positional access; MZ parameter arrays vary in length across versions.
    public subscript(p i: Int) -> JSONValue { i < count ? self[i] : .null }
}

extension KeyedDecodingContainer {
    /// Lenient field decode: MZ data files omit fields freely and differ across versions.
    func v<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
