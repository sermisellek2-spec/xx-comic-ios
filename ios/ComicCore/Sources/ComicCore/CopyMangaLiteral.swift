import Foundation

// Ordered object members also preserve the API's chapter-group order.
indirect enum CopyMangaValue {
    case object([(String, CopyMangaValue)]), array([CopyMangaValue]), string(String), number(String), bool(Bool), null
    subscript(_ key: String) -> CopyMangaValue { object?.last(where: { $0.0 == key })?.1 ?? .null }
    var object: [(String,CopyMangaValue)]? { if case .object(let value) = self { return value }; return nil }
    var array: [CopyMangaValue]? { if case .array(let value) = self { return value }; return nil }
    var string: String { if case .string(let value) = self { return value }; return "" }
    var integer: Int? { if case .number(let value) = self { return Int(value) }; return nil }
    var isTrue: Bool { if case .bool(true) = self { return true }; return false }
}

// Accept only data, never JavaScript/Python expressions or global text substitutions.
private struct CopyMangaLiteral {
    let input: [UInt16]
    var position = 0
    mutating func parse() throws -> CopyMangaValue {
        let result = try value(depth:0)
        space()
        guard position == input.count else { throw error() }
        return result
    }
    mutating func value(depth: Int) throws -> CopyMangaValue {
        space()
        guard depth <= 64, position < input.count else { throw error() }
        switch input[position] {
        case 34,39: return .string(try string())
        case 91:
            position += 1
            var result: [CopyMangaValue] = []
            if take(93) { return .array(result) }
            repeat {
                result.append(try value(depth:depth+1))
                if take(93) { return .array(result) }
                guard take(44) else { throw error() }
            } while !take(93)
            return .array(result)
        case 123:
            position += 1
            var result: [(String,CopyMangaValue)] = []
            if take(125) { return .object(result) }
            repeat {
                space()
                let key = try string()
                guard take(58) else { throw error() }
                let item = try value(depth:depth+1)
                // Match object replacement semantics without changing the first key's slot.
                if let index = result.firstIndex(where: { $0.0 == key }) { result[index].1 = item }
                else { result.append((key,item)) }
                if take(125) { return .object(result) }
                guard take(44) else { throw error() }
            } while !take(125)
            return .object(result)
        default:
            let start = position
            while position < input.count && ![44,93,125,32,9,13,10].contains(input[position]) { position += 1 }
            let token = String(decoding:input[start..<position],as:UTF16.self)
            if ["null","None"].contains(token) { return .null }
            if ["true","True"].contains(token) { return .bool(true) }
            if ["false","False"].contains(token) { return .bool(false) }
            guard token.range(of:#"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#,options:.regularExpression) != nil,
                  let number = Double(token), number.isFinite else { throw error() }
            if !token.contains(".") && !token.lowercased().contains("e") && Int64(token) == nil { throw error() }
            return .number(token)
        }
    }
    mutating func string() throws -> String {
        guard position < input.count, [34,39].contains(input[position]) else { throw error() }
        let quote = input[position]; position += 1
        var result: [UInt16] = []
        while position < input.count {
            let c = input[position]; position += 1
            if c == quote {
                var i = 0
                while i < result.count {
                    if (0xD800...0xDBFF).contains(result[i]) {
                        guard i+1 < result.count, (0xDC00...0xDFFF).contains(result[i+1]) else { throw error() }
                        i += 2
                    } else {
                        guard !(0xDC00...0xDFFF).contains(result[i]) else { throw error() }
                        i += 1
                    }
                }
                return String(decoding:result,as:UTF16.self)
            }
            guard c >= 32 else { throw error() }
            if c != 92 { result.append(c); continue }
            guard position < input.count else { throw error() }
            let escaped = input[position]; position += 1
            switch escaped {
            case 92,47,39,34: result.append(escaped)
            case 110: result.append(10)
            case 114: result.append(13)
            case 116: result.append(9)
            case 98: result.append(8)
            case 102: result.append(12)
            case 117,120:
                let length = escaped == 117 ? 4 : 2
                guard position+length <= input.count else { throw error() }
                let digits = input[position..<position+length]
                guard digits.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                      let code = UInt16(String(decoding:digits,as:UTF16.self),radix:16) else { throw error() }
                result.append(code); position += length
            default: throw error()
            }
        }
        throw error()
    }
    mutating func space() { while position < input.count && [32,9,13,10].contains(input[position]) { position += 1 } }
    mutating func take(_ c: UInt16) -> Bool {
        space()
        guard position < input.count, input[position] == c else { return false }
        position += 1; return true
    }
    func error() -> Error { NSError(domain:"CopyManga",code:1,userInfo:[NSLocalizedDescriptionKey:"拷贝漫画数据格式错误，位置 \(position)"]) }
}

func parseCopyMangaLiteral(_ input: String) throws -> CopyMangaValue {
    var parser = CopyMangaLiteral(input:Array(input.utf16))
    return try parser.parse()
}
