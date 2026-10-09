// Nachbildung der Kotlin/Java-Funktionen, die die Android-App zum Lesen von Eingaben benutzt
// (String.trim, toIntOrNull, toDoubleOrNull, roundToInt). So akzeptieren beide Apps dieselben Texte.

/// Wie Kotlins Char.isWhitespace (Java isWhitespace oder isSpaceChar).
func isKotlinWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09...0x0D, 0x1C...0x1F:
        return true
    default:
        break
    }
    switch scalar.properties.generalCategory {
    case .spaceSeparator, .lineSeparator, .paragraphSeparator:
        return true
    default:
        return false
    }
}

/// Wie Kotlins String.trim(): entfernt Leerzeichen am Anfang und Ende.
func trimmedScalars<C: Collection>(_ scalars: C) -> [Unicode.Scalar] where C.Element == Unicode.Scalar {
    let array = Array(scalars)
    var lower = 0
    var upper = array.count
    while lower < upper && isKotlinWhitespace(array[lower]) {
        lower += 1
    }
    while upper > lower && isKotlinWhitespace(array[upper - 1]) {
        upper -= 1
    }
    return Array(array[lower..<upper])
}

func makeString<C: Collection>(_ scalars: C) -> String where C.Element == Unicode.Scalar {
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars)
    return String(view)
}

/// Teilt an jedem Vorkommen von `separator`; leere Teile bleiben erhalten (wie Kotlins split).
func splitScalars(_ scalars: [Unicode.Scalar], separator: Unicode.Scalar) -> [[Unicode.Scalar]] {
    var parts: [[Unicode.Scalar]] = [[]]
    for scalar in scalars {
        if scalar == separator {
            parts.append([])
        } else {
            parts[parts.count - 1].append(scalar)
        }
    }
    return parts
}

/// Wert einer Dezimalziffer (Unicode-Kategorie Nd), wie Character.digit(c, 10) in Java.
func decimalDigitValue(_ scalar: Unicode.Scalar) -> Int? {
    if scalar.value >= 0x30 && scalar.value <= 0x39 {
        return Int(scalar.value - 0x30)
    }
    guard scalar.properties.generalCategory == .decimalNumber,
          let value = scalar.properties.numericValue
    else { return nil }
    return Int(value)
}

/// Wie Kotlins String.toIntOrNull(): optionales Vorzeichen, danach nur Ziffern, Bereich von Int32.
func kotlinToInt(_ scalars: [Unicode.Scalar]) -> Int? {
    guard let first = scalars.first else { return nil }
    var index = 0
    var negative = false
    if first == "-" || first == "+" {
        if scalars.count == 1 {
            return nil
        }
        negative = first == "-"
        index = 1
    }
    var value = 0
    while index < scalars.count {
        guard let digit = decimalDigitValue(scalars[index]) else { return nil }
        value = value * 10 + digit
        if value > 2_147_483_648 {
            return nil
        }
        index += 1
    }
    if negative {
        value = -value
    }
    if value > 2_147_483_647 {
        return nil
    }
    return value
}

private func isASCIIDigit(_ byte: UInt8) -> Bool {
    return byte >= 0x30 && byte <= 0x39
}

private func isASCIIHexDigit(_ byte: UInt8) -> Bool {
    return isASCIIDigit(byte) || (byte >= 0x41 && byte <= 0x46) || (byte >= 0x61 && byte <= 0x66)
}

private func asciiString(_ bytes: ArraySlice<UInt8>) -> String {
    return String(decoding: bytes, as: UTF8.self)
}

/// Wie Kotlins String.toDoubleOrNull() auf der JVM: Syntax von Double.parseDouble
/// (nur ASCII-Ziffern, Exponent, Hex-Gleitkommazahlen, Suffix d/f, "NaN", "Infinity").
func kotlinToDouble(_ scalars: [Unicode.Scalar]) -> Double? {
    var bytes: [UInt8] = []
    for scalar in scalars {
        guard scalar.isASCII else { return nil }
        bytes.append(UInt8(scalar.value))
    }
    // Java ignoriert Steuer- und Leerzeichen bis U+0020 am Rand.
    var lower = 0
    var upper = bytes.count
    while lower < upper && bytes[lower] <= 0x20 {
        lower += 1
    }
    while upper > lower && bytes[upper - 1] <= 0x20 {
        upper -= 1
    }
    var negative = false
    if lower < upper && (bytes[lower] == 0x2B || bytes[lower] == 0x2D) {
        negative = bytes[lower] == 0x2D
        lower += 1
    }
    let sign = negative ? "-" : ""
    let rest = asciiString(bytes[lower..<upper])
    if rest == "NaN" {
        return Double.nan
    }
    if rest == "Infinity" {
        return negative ? -Double.infinity : Double.infinity
    }
    // Optionales Typsuffix wie "8d" oder "8f".
    if upper > lower {
        let last = bytes[upper - 1]
        if last == 0x64 || last == 0x44 || last == 0x66 || last == 0x46 {
            upper -= 1
        }
    }
    let body = Array(bytes[lower..<upper])
    if body.count >= 2 && body[0] == 0x30 && (body[1] == 0x78 || body[1] == 0x58) {
        return parseJavaHexFloat(Array(body[2...]), sign: sign)
    }
    return parseJavaDecimal(body, sign: sign)
}

/// Ziffern[.Ziffern][e[+-]Ziffern] oder .Ziffern[e[+-]Ziffern]
private func parseJavaDecimal(_ body: [UInt8], sign: String) -> Double? {
    var index = 0
    let integerStart = index
    while index < body.count && isASCIIDigit(body[index]) {
        index += 1
    }
    let integerDigits = asciiString(body[integerStart..<index])
    var fractionDigits = ""
    if index < body.count && body[index] == 0x2E {
        index += 1
        let fractionStart = index
        while index < body.count && isASCIIDigit(body[index]) {
            index += 1
        }
        fractionDigits = asciiString(body[fractionStart..<index])
    }
    if integerDigits.isEmpty && fractionDigits.isEmpty {
        return nil
    }
    var exponent = "0"
    if index < body.count && (body[index] == 0x65 || body[index] == 0x45) {
        index += 1
        var exponentSign = ""
        if index < body.count && (body[index] == 0x2B || body[index] == 0x2D) {
            if body[index] == 0x2D {
                exponentSign = "-"
            }
            index += 1
        }
        let exponentStart = index
        while index < body.count && isASCIIDigit(body[index]) {
            index += 1
        }
        if exponentStart == index {
            return nil
        }
        exponent = exponentSign + asciiString(body[exponentStart..<index])
    }
    if index != body.count {
        return nil
    }
    let integerPart = integerDigits.isEmpty ? "0" : integerDigits
    let fractionPart = fractionDigits.isEmpty ? "0" : fractionDigits
    return Double(sign + integerPart + "." + fractionPart + "e" + exponent)
}

/// Hexziffern[.Hexziffern]p[+-]Ziffern (nach "0x")
private func parseJavaHexFloat(_ body: [UInt8], sign: String) -> Double? {
    var index = 0
    let integerStart = index
    while index < body.count && isASCIIHexDigit(body[index]) {
        index += 1
    }
    let integerDigits = asciiString(body[integerStart..<index])
    var fractionDigits = ""
    if index < body.count && body[index] == 0x2E {
        index += 1
        let fractionStart = index
        while index < body.count && isASCIIHexDigit(body[index]) {
            index += 1
        }
        fractionDigits = asciiString(body[fractionStart..<index])
    }
    if integerDigits.isEmpty && fractionDigits.isEmpty {
        return nil
    }
    guard index < body.count && (body[index] == 0x70 || body[index] == 0x50) else { return nil }
    index += 1
    var exponentSign = ""
    if index < body.count && (body[index] == 0x2B || body[index] == 0x2D) {
        if body[index] == 0x2D {
            exponentSign = "-"
        }
        index += 1
    }
    let exponentStart = index
    while index < body.count && isASCIIDigit(body[index]) {
        index += 1
    }
    if exponentStart == index || index != body.count {
        return nil
    }
    let integerPart = integerDigits.isEmpty ? "0" : integerDigits
    let fractionPart = fractionDigits.isEmpty ? "0" : fractionDigits
    let exponent = exponentSign + asciiString(body[exponentStart..<index])
    return Double(sign + "0x" + integerPart + "." + fractionPart + "p" + exponent)
}

/// Wie Kotlins Double.roundToInt(): kaufmännisch runden (x,5 aufwärts), begrenzt auf Int32.
func kotlinRoundToInt(_ value: Double) -> Int {
    if value.isNaN {
        return 0
    }
    if value >= 2_147_483_647 {
        return 2_147_483_647
    }
    if value <= -2_147_483_648 {
        return -2_147_483_648
    }
    let lower = value.rounded(.down)
    let rounded = value - lower >= 0.5 ? lower + 1 : lower
    return Int(rounded)
}
