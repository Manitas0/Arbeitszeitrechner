import Foundation

// Kleiner JSON-Leser und -Schreiber für das Sicherungsformat.
//
// Warum nicht JSONSerialization? Es liefert Zahlen und Wahrheitswerte beide als NSNumber.
// Unter Linux (swift-corelibs-foundation) gibt es kein CFBooleanGetTypeID, und `as? Bool` bzw.
// `as? Int` verhalten sich bei NSNumber je nach Plattform unterschiedlich (auf Apple-Plattformen
// ist z. B. NSNumber(1) `as? Bool` gleich true). Ein eigener Parser behält den JSON-Typ und
// verhält sich auf iOS, macOS und Linux identisch. Die opt*-Zugriffe bilden die Nachsicht von
// org.json nach (optInt, optString, optBoolean, optJSONArray, optJSONObject).

/// Ein JSON-Wert. Zahlen behalten ihren Text, Objekte die Reihenfolge der Schlüssel.
enum JSONValue {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([JSONMember])
}

struct JSONMember {
    var key: String
    var value: JSONValue

    init(_ key: String, _ value: JSONValue) {
        self.key = key
        self.value = value
    }
}

// MARK: - Zugriff

extension JSONValue {

    /// Wert zu `key` in einem Objekt; bei doppelten Schlüsseln gewinnt der letzte (wie Android).
    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        for member in members.reversed() where member.key == key {
            return member.value
        }
        return nil
    }

    var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }

    var isObject: Bool {
        if case .object = self {
            return true
        }
        return false
    }

    var stringValue: String? {
        if case .string(let text) = self {
            return text
        }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    /// Ganzzahl wie Number.intValue() in Java (Nachkommastellen werden abgeschnitten).
    var intValue: Int? {
        if case .number(let text) = self {
            return JSONValue.javaInt(fromNumberText: text)
        }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let items) = self {
            return items
        }
        return nil
    }

    var objectMembers: [JSONMember]? {
        if case .object(let members) = self {
            return members
        }
        return nil
    }

    /// Schlüssel und Werte eines Objekts (letzter Schlüssel gewinnt), sonst leer.
    var objectDictionary: [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for member in objectMembers ?? [] {
            result[member.key] = member.value
        }
        return result
    }

    static func javaInt(fromNumberText text: String) -> Int? {
        if let exact = Int64(text) {
            // Wie intValue() bei Long: die unteren 32 Bit.
            return Int(Int32(truncatingIfNeeded: exact))
        }
        guard let double = Double(text) else { return nil }
        if double.isNaN {
            return 0
        }
        if double >= 2_147_483_647 {
            return 2_147_483_647
        }
        if double <= -2_147_483_648 {
            return -2_147_483_648
        }
        return Int(double)
    }

    // MARK: org.json-Nachbildung

    /// Wie JSONObject.optString(key): fehlend oder null -> "", Zahlen und Wahrheitswerte als Text.
    func optString(_ key: String) -> String {
        guard let value = self[key] else { return "" }
        switch value {
        case .null:
            return ""
        case .string(let text):
            return text
        case .number(let text):
            return text
        case .bool(let flag):
            return flag ? "true" : "false"
        case .array, .object:
            return value.serialized()
        }
    }

    /// Wie JSONObject.optInt(key, fallback): Zahlen und Zahl-Texte ("30"), sonst `fallback`.
    func optInt(_ key: String, _ fallback: Int) -> Int {
        guard let value = self[key] else { return fallback }
        switch value {
        case .number(let text):
            return JSONValue.javaInt(fromNumberText: text) ?? fallback
        case .string(let text):
            guard let literal = JSONParser.numberLiteral(text) else { return fallback }
            return JSONValue.javaInt(fromNumberText: literal) ?? fallback
        default:
            return fallback
        }
    }

    /// Wie JSONObject.optBoolean(key, fallback): true/false oder die Texte "true"/"false".
    func optBoolean(_ key: String, _ fallback: Bool) -> Bool {
        guard let value = self[key] else { return fallback }
        switch value {
        case .bool(let flag):
            return flag
        case .string(let text):
            let lower = text.lowercased()
            if lower == "true" {
                return true
            }
            if lower == "false" {
                return false
            }
            return fallback
        default:
            return fallback
        }
    }

    /// Wie JSONObject.optJSONArray(key).
    func optArray(_ key: String) -> [JSONValue]? {
        return self[key]?.arrayValue
    }

    /// Wie JSONObject.optJSONObject(key): das Objekt oder nil.
    func optObject(_ key: String) -> JSONValue? {
        guard let value = self[key], value.isObject else { return nil }
        return value
    }

    // MARK: Vergleich

    /// Gleichheit unabhängig von der Reihenfolge der Schlüssel; Zahlen werden nach Wert verglichen.
    func isSemanticallyEqual(to other: JSONValue) -> Bool {
        switch (self, other) {
        case (.null, .null):
            return true
        case (.bool(let lhs), .bool(let rhs)):
            return lhs == rhs
        case (.number(let lhs), .number(let rhs)):
            if lhs == rhs {
                return true
            }
            guard let left = Double(lhs), let right = Double(rhs) else { return false }
            return left == right
        case (.string(let lhs), .string(let rhs)):
            return lhs == rhs
        case (.array(let lhs), .array(let rhs)):
            guard lhs.count == rhs.count else { return false }
            for index in 0..<lhs.count where !lhs[index].isSemanticallyEqual(to: rhs[index]) {
                return false
            }
            return true
        case (.object, .object):
            let left = objectDictionary
            let right = other.objectDictionary
            guard left.count == right.count else { return false }
            for (key, value) in left {
                guard let otherValue = right[key], value.isSemanticallyEqual(to: otherValue) else { return false }
            }
            return true
        default:
            return false
        }
    }
}

// MARK: - Umwandlung von [String: Any]

extension JSONValue {

    /// Wandelt Werte aus `[String: Any]` (z. B. von JSONSerialization) um.
    /// NSNumber werden über den Objective-C-Typcode unterschieden: "c" steht für einen
    /// Wahrheitswert (CFBoolean auf Apple-Plattformen, NSNumber(value: Bool) unter Linux).
    /// Reine Swift-Werte (Bool, Int, Double) werden direkt erkannt, falls sie unter Linux
    /// nicht als NSNumber gebrückt werden.
    init(any value: Any) {
        if value is NSNull {
            self = .null
        } else if let text = value as? String {
            self = .string(text)
        } else if let dictionary = value as? [String: Any] {
            let sorted = dictionary.sorted { $0.key < $1.key }
            self = .object(sorted.map { JSONMember($0.key, JSONValue(any: $0.value)) })
        } else if let array = value as? [Any] {
            self = .array(array.map { JSONValue(any: $0) })
        } else if let number = value as? NSNumber {
            self = JSONValue(number: number)
        } else if let flag = value as? Bool {
            self = .bool(flag)
        } else if let integer = value as? Int {
            self = .number(String(integer))
        } else if let integer = value as? Int64 {
            self = .number(String(integer))
        } else if let integer = value as? Int32 {
            self = .number(String(integer))
        } else if let double = value as? Double {
            self = JSONValue.numberValue(from: double)
        } else {
            self = .null
        }
    }

    private init(number: NSNumber) {
        let typeCode = Int(number.objCType.pointee)
        switch typeCode {
        case 0x63, 0x42: // "c" (Wahrheitswert), "B" (C99-Bool)
            self = .bool(number.boolValue)
        case 0x66, 0x64: // "f", "d"
            self = JSONValue.numberValue(from: number.doubleValue)
        default:
            self = .number(String(number.int64Value))
        }
    }

    private static func numberValue(from double: Double) -> JSONValue {
        guard double.isFinite else { return .null }
        if double == double.rounded() && abs(double) < 1e15 {
            return .number(String(Int64(double)))
        }
        return .number(String(double))
    }
}

// MARK: - Schreiben

extension JSONValue {

    /// JSON-Text. Mit `indent` eingerückt (wie JSONObject.toString(2)), sonst kompakt.
    func serialized(indent: Int? = nil) -> String {
        var output = ""
        write(to: &output, indent: indent, level: 0)
        return output
    }

    private func write(to output: inout String, indent: Int?, level: Int) {
        switch self {
        case .null:
            output += "null"
        case .bool(let flag):
            output += flag ? "true" : "false"
        case .number(let text):
            output += text
        case .string(let text):
            JSONValue.writeString(text, to: &output)
        case .array(let items):
            if items.isEmpty {
                output += "[]"
                return
            }
            output += "["
            for (index, item) in items.enumerated() {
                if index > 0 {
                    output += ","
                }
                JSONValue.writeNewline(to: &output, indent: indent, level: level + 1)
                item.write(to: &output, indent: indent, level: level + 1)
            }
            JSONValue.writeNewline(to: &output, indent: indent, level: level)
            output += "]"
        case .object(let members):
            if members.isEmpty {
                output += "{}"
                return
            }
            output += "{"
            for (index, member) in members.enumerated() {
                if index > 0 {
                    output += ","
                }
                JSONValue.writeNewline(to: &output, indent: indent, level: level + 1)
                JSONValue.writeString(member.key, to: &output)
                output += indent == nil ? ":" : ": "
                member.value.write(to: &output, indent: indent, level: level + 1)
            }
            JSONValue.writeNewline(to: &output, indent: indent, level: level)
            output += "}"
        }
    }

    private static func writeNewline(to output: inout String, indent: Int?, level: Int) {
        guard let indent = indent else { return }
        output += "\n"
        output += String(repeating: " ", count: indent * level)
    }

    private static func writeString(_ text: String, to output: inout String) {
        output += "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22:
                output += "\\\""
            case 0x5C:
                output += "\\\\"
            case 0x0A:
                output += "\\n"
            case 0x0D:
                output += "\\r"
            case 0x09:
                output += "\\t"
            case 0x08:
                output += "\\b"
            case 0x0C:
                output += "\\f"
            case 0x00..<0x20:
                let hex = String(scalar.value, radix: 16)
                output += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}

// MARK: - Lesen

/// JSON-Parser nach RFC 8259 mit den Erleichterungen von org.json (Android):
/// Text nach dem ersten Wert wird auf Wunsch ignoriert, unbekannte Escapes ergeben das Zeichen selbst.
struct JSONParser {
    private let bytes: [UInt8]
    private var position = 0
    private var depth = 0
    private static let maxDepth = 512

    private init(_ text: String) {
        bytes = Array(text.utf8)
    }

    /// Liest den ersten JSON-Wert aus `text`. Mit `allowTrailingContent` wird alles danach
    /// ignoriert (wie `JSONObject(String)` unter Android), sonst sind nur Leerzeichen erlaubt.
    static func parse(_ text: String, allowTrailingContent: Bool = false) -> JSONValue? {
        var parser = JSONParser(text)
        guard let value = parser.parseValue() else { return nil }
        if !allowTrailingContent {
            parser.skipWhitespace()
            if parser.position != parser.bytes.count {
                return nil
            }
        }
        return value
    }

    /// Der Text, wenn er genau eine JSON-Zahl ist (z. B. "30" oder "1e2"), sonst nil.
    static func numberLiteral(_ text: String) -> String? {
        var parser = JSONParser(text)
        guard let value = parser.parseNumber(), parser.position == parser.bytes.count else { return nil }
        if case .number(let literal) = value {
            return literal
        }
        return nil
    }

    private mutating func skipWhitespace() {
        while position < bytes.count {
            let byte = bytes[position]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                position += 1
            } else {
                return
            }
        }
    }

    private mutating func parseValue() -> JSONValue? {
        skipWhitespace()
        guard position < bytes.count else { return nil }
        switch bytes[position] {
        case 0x7B: // {
            return parseObject()
        case 0x5B: // [
            return parseArray()
        case 0x22: // "
            guard let text = parseString() else { return nil }
            return .string(text)
        case 0x74: // t
            return parseLiteral("true", value: .bool(true))
        case 0x66: // f
            return parseLiteral("false", value: .bool(false))
        case 0x6E: // n
            return parseLiteral("null", value: .null)
        default:
            return parseNumber()
        }
    }

    private mutating func parseLiteral(_ literal: String, value: JSONValue) -> JSONValue? {
        let expected = Array(literal.utf8)
        guard position + expected.count <= bytes.count else { return nil }
        for offset in 0..<expected.count where bytes[position + offset] != expected[offset] {
            return nil
        }
        position += expected.count
        return value
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        return byte >= 0x30 && byte <= 0x39
    }

    private mutating func skipDigits() {
        while position < bytes.count && isDigit(bytes[position]) {
            position += 1
        }
    }

    private mutating func parseNumber() -> JSONValue? {
        let start = position
        if position < bytes.count && bytes[position] == 0x2D { // -
            position += 1
        }
        guard position < bytes.count, isDigit(bytes[position]) else { return nil }
        if bytes[position] == 0x30 {
            position += 1
        } else {
            skipDigits()
        }
        if position < bytes.count && bytes[position] == 0x2E { // .
            position += 1
            guard position < bytes.count, isDigit(bytes[position]) else { return nil }
            skipDigits()
        }
        if position < bytes.count && (bytes[position] == 0x65 || bytes[position] == 0x45) { // e E
            position += 1
            if position < bytes.count && (bytes[position] == 0x2B || bytes[position] == 0x2D) {
                position += 1
            }
            guard position < bytes.count, isDigit(bytes[position]) else { return nil }
            skipDigits()
        }
        return .number(String(decoding: bytes[start..<position], as: UTF8.self))
    }

    private mutating func readHex4() -> UInt32? {
        guard position + 4 <= bytes.count else { return nil }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[position]
            var digit: UInt32 = 0
            if byte >= 0x30 && byte <= 0x39 {
                digit = UInt32(byte - 0x30)
            } else if byte >= 0x41 && byte <= 0x46 {
                digit = UInt32(byte - 0x41) + 10
            } else if byte >= 0x61 && byte <= 0x66 {
                digit = UInt32(byte - 0x61) + 10
            } else {
                return nil
            }
            value = value * 16 + digit
            position += 1
        }
        return value
    }

    private mutating func parseString() -> String? {
        position += 1 // öffnendes Anführungszeichen
        var buffer: [UInt8] = []
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            if byte == 0x22 {
                return String(decoding: buffer, as: UTF8.self)
            }
            if byte != 0x5C {
                buffer.append(byte)
                continue
            }
            guard position < bytes.count else { return nil }
            let escape = bytes[position]
            position += 1
            switch escape {
            case 0x62: // b
                buffer.append(0x08)
            case 0x66: // f
                buffer.append(0x0C)
            case 0x6E: // n
                buffer.append(0x0A)
            case 0x72: // r
                buffer.append(0x0D)
            case 0x74: // t
                buffer.append(0x09)
            case 0x75: // u
                guard let unit = readHex4() else { return nil }
                let scalar = decodeEscapedScalar(firstUnit: unit)
                buffer.append(contentsOf: Array(String(Character(scalar)).utf8))
            default:
                // \" \\ \/ und unbekannte Escapes ergeben das Zeichen selbst (wie Android).
                buffer.append(escape)
            }
        }
        return nil // nicht abgeschlossen
    }

    /// Setzt UTF-16-Ersatzpaare (z. B. D83D + DE00) zusammen; einzelne Hälften werden zu U+FFFD.
    private mutating func decodeEscapedScalar(firstUnit unit: UInt32) -> Unicode.Scalar {
        let replacement: Unicode.Scalar = "\u{FFFD}"
        if unit >= 0xD800 && unit < 0xDC00 {
            let saved = position
            if position + 6 <= bytes.count && bytes[position] == 0x5C && bytes[position + 1] == 0x75 {
                position += 2
                if let low = readHex4(), low >= 0xDC00 && low < 0xE000 {
                    let value = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                    return Unicode.Scalar(value) ?? replacement
                }
            }
            position = saved
            return replacement
        }
        if unit >= 0xDC00 && unit < 0xE000 {
            return replacement
        }
        return Unicode.Scalar(unit) ?? replacement
    }

    private mutating func parseArray() -> JSONValue? {
        guard depth < JSONParser.maxDepth else { return nil }
        depth += 1
        defer { depth -= 1 }
        position += 1 // [
        var items: [JSONValue] = []
        skipWhitespace()
        if position < bytes.count && bytes[position] == 0x5D { // ]
            position += 1
            return .array(items)
        }
        while let item = parseValue() {
            items.append(item)
            skipWhitespace()
            guard position < bytes.count else { return nil }
            let byte = bytes[position]
            position += 1
            if byte == 0x5D {
                return .array(items)
            }
            if byte != 0x2C { // ,
                return nil
            }
        }
        return nil
    }

    private mutating func parseObject() -> JSONValue? {
        guard depth < JSONParser.maxDepth else { return nil }
        depth += 1
        defer { depth -= 1 }
        position += 1 // {
        var members: [JSONMember] = []
        skipWhitespace()
        if position < bytes.count && bytes[position] == 0x7D { // }
            position += 1
            return .object(members)
        }
        while position < bytes.count && bytes[position] == 0x22 {
            guard let key = parseString() else { return nil }
            skipWhitespace()
            guard position < bytes.count, bytes[position] == 0x3A else { return nil } // :
            position += 1
            guard let value = parseValue() else { return nil }
            members.append(JSONMember(key, value))
            skipWhitespace()
            guard position < bytes.count else { return nil }
            let byte = bytes[position]
            position += 1
            if byte == 0x7D {
                return .object(members)
            }
            if byte != 0x2C {
                return nil
            }
            skipWhitespace()
        }
        return nil
    }
}
