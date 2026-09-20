import Foundation

// Data-only decoder: packer bodies are located but never interpreted or executed.
enum ManhuaguiReader {
    static func images(_ html: String) throws -> [String] {
        try Task.checkCancellation()
        guard html.utf8.count <= GuiBudget.limit else { throw guiError("输入超过32MiB限制") }
        var budget = GuiBudget()
        guard let root = try extract(html,depth:0,budget:&budget) else { throw guiError("未找到章节图片配置") }
        let segments = root["path"].string.split(separator:"/")
        let path = "/" + segments.map { guiEncode(String($0)).replacingOccurrences(of:"+",with:"%20") }.joined(separator:"/") + (segments.isEmpty ? "" : "/")
        try budget.expand(path.utf8.count)
        var images: [String] = [], seen = Set<String>()
        for file in root["files"].array ?? [] {
            try Task.checkCancellation()
            let file = scalar(file)
            guard !file.isEmpty else { continue }
            let value = "https://eu2.hamreus.com"+path+file+"?e="+scalar(root["sl"]["e"])+"&m="+scalar(root["sl"]["m"])
            try budget.expand(value.utf8.count)
            guard let url = URL(string:value), url.scheme == "https", url.host == "eu2.hamreus.com",
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }),
                  value.range(of:#"%(?![0-9a-fA-F]{2})"#,options:.regularExpression) == nil else { throw guiError("图片网址无效") }
            if seen.insert(value).inserted { images.append(value) }
        }
        guard !images.isEmpty else { throw guiError("章节图片列表为空") }; return images
    }
    private static func scalar(_ value: CopyMangaValue) -> String {
        switch value { case .string(let s),.number(let s): return s; case .bool(let b): return String(b); default: return "" }
    }
    private static func extract(_ text: String, depth: Int, budget: inout GuiBudget) throws -> CopyMangaValue? {
        try Task.checkCancellation()
        guard depth <= 4 else { throw guiError("解包深度超过4层") }
        let units = Array(text.utf16), ns = text as NSString
        var invocations: [Int] = []
        let functions = try NSRegularExpression(pattern:#"function\(p,a,c,k,e,d\)"#)
        for match in functions.matches(in:text,range:NSRange(location:0,length:units.count)) {
            try Task.checkCancellation()
            let from = NSMaxRange(match.range)
            guard let brace = try find(123,in:units,from:from,budget:&budget),
                  let end = try matchingBrace(units,start:brace,budget:&budget),
                  let open = try find(40,in:units,from:end+1,budget:&budget) else { continue }
            invocations.append(open)
        }
        var unpacked = false
        for open in invocations {
            try Task.checkCancellation()
            if let args = try arguments(units,open:open) {
                unpacked = true
                if let result = try extract(unpack(args,budget:&budget),depth:depth+1,budget:&budget) { return result }
            }
        }
        if !unpacked {
            // Java's legacy invocation fallback is used only when no function invocation parsed.
            let pattern = #"\(\s*(["'])((?:\\.|(?!\1)[\s\S])*)\1\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(["'])((?:\\.|(?!\5)[\s\S])*)\5\s*(?:\.\s*split|\[[^\]]*\])\s*\(\s*(["'])((?:\\.|(?!\7)[\s\S])*)\7\s*\)"#
            for match in try NSRegularExpression(pattern:pattern).matches(in:text,range:NSRange(location:0,length:units.count)) {
                try Task.checkCancellation()
                if let args = try arguments(units,open:match.range.location), let result = try extract(unpack(args,budget:&budget),depth:depth+1,budget:&budget) { return result }
            }
        }
        let markers = try NSRegularExpression(pattern:#"SMH(?:\.imgData|\["imgData"\]|\['imgData'\])"#)
        for match in markers.matches(in:text,range:NSRange(location:0,length:units.count)) {
            try Task.checkCancellation()
            guard let paren = try find(40,in:units,from:NSMaxRange(match.range),budget:&budget),
                  let start = try find(123,in:units,from:paren,budget:&budget),
                  let end = try matchingBrace(units,start:start,budget:&budget) else { continue }
            if let root = try literal(ns,start:start,end:end,budget:&budget), !root["path"].string.isEmpty, root["files"].array != nil, root["sl"].object != nil { return root }
        }
        var search = 0
        while let start = try find(123,in:units,from:search,budget:&budget) {
            if let end = try matchingBrace(units,start:start,budget:&budget),
               let root = try literal(ns,start:start,end:end,budget:&budget), let result = canonical(root) { return result }
            search = start+1
        }
        return nil
    }
    private static func literal(_ text: NSString, start: Int, end: Int, budget: inout GuiBudget) throws -> CopyMangaValue? {
        try budget.scan(end-start+1)
        do { return try parseCopyMangaLiteral(text.substring(with:NSRange(location:start,length:end-start+1)),loose:true) }
        catch is CancellationError { throw CancellationError() }
        catch { return nil }
    }
    private static func canonical(_ root: CopyMangaValue) -> CopyMangaValue? {
        guard let fields = root.object else { return nil }
        var path = root["path"].string, files = root["files"].array, signature = root["sl"].object
        for (_,value) in fields {
            if files == nil, let array = value.array, !array.isEmpty,
               array.allSatisfy({ scalar($0).range(of:#"(?i).+\.(jpe?g|png|webp|gif|bmp)(\?.*)?$"#,options:.regularExpression) != nil }) { files = array }
            else if path.isEmpty, value.string.contains("/") { path = value.string }
            else if signature == nil, let object = value.object, object.contains(where: { $0.0 == "e" || $0.0 == "m" }) { signature = object }
        }
        guard !path.isEmpty, let files else { return nil }
        return .object([("path",.string(path)),("files",.array(files)),("sl",.object(signature ?? []))])
    }
    // Charge each suffix search in bounded chunks, including missing targets.
    private static func find(_ unit: UInt16, in input: [UInt16], from: Int, budget: inout GuiBudget) throws -> Int? {
        var position = from
        while position < input.count {
            let end = min(position+4096,input.count)
            try budget.scan(end-position)
            if let match = input[position..<end].firstIndex(of:unit) { return match }
            position = end
        }
        return nil
    }
    // Like Java matchingBrace, quote state begins at this candidate, never in unrelated HTML/JS.
    private static func matchingBrace(_ input: [UInt16], start: Int, budget: inout GuiBudget) throws -> Int? {
        var depth = 0, quote: UInt16?, escape = false
        for i in start..<input.count {
            if (i-start) % 4096 == 0 { try budget.scan(min(4096,input.count-i)) }
            let c = input[i]
            if let q = quote { if escape { escape = false } else if c == 92 { escape = true } else if c == q { quote = nil }; continue }
            if c == 34 || c == 39 { quote = c }
            else if c == 123 { guard depth < 262144 else { throw guiError("对象嵌套超限") }; depth += 1 }
            else if c == 125 { depth -= 1; if depth == 0 { return i } }
        }
        return nil
    }
    private struct Args { let payload: String; let radix: Int; let count: Int; let dictionary: String; let separator: String }
    private static func arguments(_ input: [UInt16], open: Int) throws -> Args? {
        var cursor = GuiCursor(input:input,position:open+1)
        guard let payload = try cursor.string(), cursor.take(44), let radix = try cursor.integer(), cursor.take(44), let count = try cursor.integer(), cursor.take(44), let dictionary = try cursor.string() else { return nil }
        guard (2...62).contains(radix), count <= 262144 else { throw guiError("解包进制或字典条目数无效") }
        let tailStart = cursor.position
        var nesting = 0
        while cursor.position < input.count {
            if cursor.position % 4096 == 0 { try Task.checkCancellation() }
            let c = input[cursor.position]
            if c == 34 || c == 39 { guard try cursor.string() != nil else { return nil }; continue }
            if c == 40 { nesting += 1 } else if c == 41 { if nesting == 0 { break }; nesting -= 1 } else if c == 44 && nesting == 0 { break }
            cursor.position += 1
        }
        guard cursor.position < input.count else { return nil }
        let tail = String(decoding:input[tailStart..<cursor.position],as:UTF16.self)
        let split = guiFirst(#"(?:split\s*|\[\s*['"]split['"]\s*\]\s*)\(\s*((?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'))\s*\)"#,tail)
        let separator = split.isEmpty ? "|" : try parseCopyMangaLiteral(split).string
        return Args(payload:payload,radix:radix,count:count,dictionary:dictionary,separator:separator)
    }
    private static func unpack(_ args: Args, budget: inout GuiBudget) throws -> String {
        var best = [args.dictionary], dictionary: [String]?
        func split(_ text: String) throws -> [String]? {
            for sep in [args.separator,"|",","] where !sep.isEmpty {
                try Task.checkCancellation()
                var parts: [String] = [], start = text.startIndex
                while let range = text.range(of:sep,range:start..<text.endIndex) {
                    try Task.checkCancellation()
                    guard parts.count < 262143 else { throw guiError("解包字典条目超限") }
                    parts.append(String(text[start..<range.lowerBound])); start = range.upperBound
                }
                parts.append(String(text[start...]))
                if parts.count > best.count { best = parts }
                if parts.count >= args.count { return parts }
            }
            return nil
        }
        dictionary = try split(args.dictionary)
        if dictionary == nil, let decoded = try GuiLZ.decode(args.dictionary,budget:&budget) { dictionary = try split(decoded) }
        let values = dictionary ?? best
        try budget.dictionary(values.reduce(0) { $0 + $1.utf16.count*2 })
        let input = Array(args.payload.utf16)
        var result: [UInt16] = [], position = 0
        while position < input.count {
            if position % 4096 == 0 { try Task.checkCancellation() }
            let start = position
            if digit(input[position]) != nil {
                var index: Int? = 0
                while position < input.count, let d = digit(input[position]) {
                    if position % 4096 == 0 { try Task.checkCancellation() }
                    if let current = index, d < args.radix, current <= (Int.max-d)/args.radix { index = current*args.radix+d } else { index = nil }
                    position += 1
                }
                if let index, index < values.count, !values[index].isEmpty {
                    try budget.expand(values[index].utf16.count*2)
                    result.append(contentsOf:values[index].utf16); continue
                }
            } else { position += 1 }
            try budget.expand((position-start)*2); result.append(contentsOf:input[start..<position])
        }
        return String(decoding:result,as:UTF16.self)
    }
    private static func digit(_ c: UInt16) -> Int? {
        if (48...57).contains(c) { return Int(c-48) }; if (97...122).contains(c) { return Int(c-97)+10 }; if (65...90).contains(c) { return Int(c-65)+36 }; return nil
    }
}

private struct GuiCursor {
    let input: [UInt16]
    var position: Int
    mutating func space() { while position < input.count && [32,9,13,10].contains(input[position]) { position += 1 } }
    mutating func take(_ c: UInt16) -> Bool { space(); guard position < input.count, input[position] == c else { return false }; position += 1; return true }
    mutating func integer() throws -> Int? {
        space(); let start = position
        while position < input.count && (48...57).contains(input[position]) { position += 1 }
        guard position > start else { return nil }
        guard let value = Int32(String(decoding:input[start..<position],as:UTF16.self)) else { throw guiError("解包数字溢出") }; return Int(value)
    }
    mutating func string() throws -> String? {
        space(); guard position < input.count, [34,39].contains(input[position]) else { return nil }
        let start = position, quote = input[position]; position += 1
        var escaped = false
        while position < input.count {
            if position % 4096 == 0 { try Task.checkCancellation() }
            let c = input[position]; position += 1
            if escaped { escaped = false } else if c == 92 { escaped = true } else if c == quote {
                return try parseCopyMangaLiteral(String(decoding:input[start..<position],as:UTF16.self)).string
            }
        }
        throw guiError("解包字符串截断")
    }
}

private struct GuiBudget {
    static let limit = 32*1024*1024
    private var expanded = 0, dictionaryBytes = 0, scanned = 0
    mutating func expand(_ size: Int) throws { guard size <= Self.limit-expanded else { throw guiError("展开超过32MiB限制") }; expanded += size }
    mutating func dictionary(_ size: Int) throws { guard size <= Self.limit-dictionaryBytes else { throw guiError("累计字典超过32MiB限制") }; dictionaryBytes += size }
    // Bound repeated candidate scans as well as allocations on adversarial nested objects.
    mutating func scan(_ size: Int) throws { guard size <= Self.limit*4-scanned else { throw guiError("解析扫描预算超限") }; scanned += size; try Task.checkCancellation() }
}

// LZString's Base64 bit stream stores UTF16 code units, not Unicode scalars.
private enum GuiLZ {
    static func decode(_ input: String, budget: inout GuiBudget) throws -> String? {
        guard !input.isEmpty, input.range(of:#"^[A-Za-z0-9+/]+=*$"#,options:.regularExpression) != nil else { return nil }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=".utf8)
        let bytes = Array(input.utf8)
        var offset = 0, mask = 32
        func bits(_ count: Int) -> Int? {
            var result = 0
            for bit in 0..<count {
                guard offset < bytes.count, let value = alphabet.firstIndex(of:bytes[offset]) else { return nil }
                if value & mask != 0 { result |= 1 << bit }
                mask >>= 1
                if mask == 0 { mask = 32; offset += 1 }
            }
            return result
        }
        guard let initial = bits(2), initial < 2, let unit = bits(initial == 0 ? 8 : 16) else { return nil }
        var dictionary: [[UInt16]] = [[],[],[],[UInt16(unit)]]
        var previous = [UInt16(unit)], output = previous, enlargeIn = 4, width = 3
        try budget.dictionary(2); try budget.expand(2)
        func add(_ entry: [UInt16], budget: inout GuiBudget) throws {
            guard dictionary.count < 262144 else { throw guiError("LZ字典条目超限") }
            try budget.dictionary(entry.count*2); dictionary.append(entry)
        }
        while true {
            try Task.checkCancellation()
            guard var code = bits(width) else { return nil }
            if code == 0 || code == 1 {
                guard let next = bits(code == 0 ? 8 : 16) else { return nil }
                try add([UInt16(next)],budget:&budget); code = dictionary.count-1; enlargeIn -= 1
            } else if code == 2 { return String(decoding:output,as:UTF16.self) }
            if enlargeIn == 0 { enlargeIn = 1 << width; width += 1 }
            let entry: [UInt16]
            if code < dictionary.count, !dictionary[code].isEmpty { entry = dictionary[code] }
            else if code == dictionary.count { entry = previous + [previous[0]] }
            else { return nil }
            try budget.expand(entry.count*2); output.append(contentsOf:entry)
            try add(previous + [entry[0]],budget:&budget)
            enlargeIn -= 1; previous = entry
            if enlargeIn == 0 { enlargeIn = 1 << width; width += 1 }
        }
    }
}
