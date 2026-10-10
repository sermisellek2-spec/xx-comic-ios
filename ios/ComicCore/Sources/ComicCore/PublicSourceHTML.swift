import Foundation

public final class PublicHTMLElement {
    public enum Child {
        case element(PublicHTMLElement)
        case text(String)
    }

    public let tag: String
    public let attributes: [String: String]
    public let baseUri: String
    public weak var parent: PublicHTMLElement?
    public fileprivate(set) var children: [Child] = []
    public fileprivate(set) var rawData: String = ""
    private let classes: Set<String>

    public init(tag: String, attributes: [String: String], baseUri: String) {
        self.tag = tag.lowercased()
        self.attributes = attributes
        self.baseUri = baseUri
        if let cls = attributes["class"], !cls.isEmpty {
            self.classes = Set(cls.split(whereSeparator: \.isWhitespace).map(String.init))
        } else {
            self.classes = []
        }
    }

    public func attr(_ name: String) -> String {
        attributes[name.lowercased()] ?? ""
    }

    public func hasAttr(_ name: String) -> Bool {
        attributes[name.lowercased()] != nil
    }

    public func absUrl(_ attributeKey: String) -> String {
        let value = attr(attributeKey).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        return PublicSourceImages.resolve(baseUri, value)
    }

    public func data() -> String {
        rawData
    }

    public func ownText() -> String {
        var buffer = ""
        for child in children {
            if case .text(let t) = child {
                buffer.append(t)
                buffer.append(" ")
            }
        }
        return Self.normalizeWhitespace(buffer)
    }

    public func text() -> String {
        var buffer = ""
        appendText(into: &buffer)
        return Self.normalizeWhitespace(buffer)
    }

    private func appendText(into buffer: inout String) {
        if tag == "script" || tag == "style" { return }
        for child in children {
            switch child {
            case .text(let t):
                buffer.append(t)
                buffer.append(" ")
            case .element(let el):
                el.appendText(into: &buffer)
                buffer.append(" ")
            }
        }
    }

    fileprivate static func normalizeWhitespace(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        var lastWasSpace = true
        for scalar in input.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            } else {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            }
        }
        if out.hasSuffix(" ") {
            out.removeLast()
        }
        return out
    }

    public func select(_ css: String) -> [PublicHTMLElement] {
        let trimmed = css.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let chains = PublicCSSParser.parseSelectorList(trimmed)
        guard !chains.isEmpty else { return [] }
        var results: [PublicHTMLElement] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ node: PublicHTMLElement) {
            if node.tag != "#document" {
                for chain in chains {
                    if PublicCSSParser.matchesChain(chain, element: node, scopeRoot: self) {
                        let id = ObjectIdentifier(node)
                        if seen.insert(id).inserted {
                            results.append(node)
                        }
                        break
                    }
                }
            }
            for child in node.children {
                if case .element(let childEl) = child {
                    visit(childEl)
                }
            }
        }
        visit(self)
        return results
    }

    public func selectFirst(_ css: String) -> PublicHTMLElement? {
        let trimmed = css.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let chains = PublicCSSParser.parseSelectorList(trimmed)
        guard !chains.isEmpty else { return nil }
        func find(_ node: PublicHTMLElement) -> PublicHTMLElement? {
            if node.tag != "#document" {
                for chain in chains {
                    if PublicCSSParser.matchesChain(chain, element: node, scopeRoot: self) {
                        return node
                    }
                }
            }
            for child in node.children {
                if case .element(let childEl) = child {
                    if let found = find(childEl) {
                        return found
                    }
                }
            }
            return nil
        }
        return find(self)
    }

    fileprivate func hasClass(_ name: String) -> Bool {
        classes.contains(name)
    }
}

public final class PublicHTMLDocument {
    public let root: PublicHTMLElement

    private init(root: PublicHTMLElement) {
        self.root = root
    }

    public func select(_ css: String) -> [PublicHTMLElement] {
        root.select(css)
    }

    public func selectFirst(_ css: String) -> PublicHTMLElement? {
        root.selectFirst(css)
    }

    public func title() -> String {
        root.selectFirst("title")?.text() ?? ""
    }

    public func text() -> String {
        root.text()
    }

    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img",
        "input", "link", "meta", "param", "source", "track", "wbr"
    ]

    private static let rawTextTags: Set<String> = [
        "script", "style", "title", "textarea"
    ]

    private static let blockClosePTags: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "div", "dl",
        "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3",
        "h4", "h5", "h6", "header", "hgroup", "hr", "main", "menu", "nav",
        "ol", "p", "pre", "section", "table", "ul"
    ]

    private static let scopeBoundaryTags: Set<String> = [
        "applet", "caption", "html", "table", "td", "th", "marquee", "object",
        "template", "body", "div", "ul", "ol", "dl", "section", "article",
        "main", "aside", "header", "footer", "nav", "form", "select"
    ]

    private static let inlineTags: Set<String> = [
        "a", "abbr", "acronym", "b", "bdi", "bdo", "big", "cite", "code", "data",
        "del", "dfn", "em", "font", "i", "ins", "kbd", "label", "mark", "nobr",
        "output", "p", "q", "rp", "rt", "ruby", "s", "samp", "small", "span",
        "strike", "strong", "sub", "sup", "time", "tt", "u", "var"
    ]

    public static func parse(_ html: String, baseUri: String = "") -> PublicHTMLDocument {
        let root = PublicHTMLElement(tag: "#document", attributes: [:], baseUri: baseUri)
        var stack: [PublicHTMLElement] = [root]
        let bytes = Array(html.utf8)
        let n = bytes.count
        var i = 0

        func isSpace(_ b: UInt8) -> Bool {
            b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == 0x0C
        }

        func isAlpha(_ b: UInt8) -> Bool {
            (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
        }

        func isTagChar(_ b: UInt8) -> Bool {
            isAlpha(b) || (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x5F || b == 0x3A
        }

        func appendTextSlice(_ start: Int, _ end: Int) {
            guard end > start else { return }
            let raw = String(decoding: bytes[start..<end], as: UTF8.self)
            let decoded = HTML4EntityDecoder.decode(raw)
            stack.last?.children.append(.text(decoded))
        }

        while i < n {
            let textStart = i
            while i < n && bytes[i] != 0x3C { // '<'
                i += 1
            }
            if i > textStart {
                appendTextSlice(textStart, i)
            }
            if i >= n { break }

            // At '<'
            if i + 3 < n && bytes[i + 1] == 0x21 && bytes[i + 2] == 0x2D && bytes[i + 3] == 0x2D {
                // Comment <!-- ... -->
                i += 4
                while i + 2 < n {
                    if bytes[i] == 0x2D && bytes[i + 1] == 0x2D && bytes[i + 2] == 0x3E {
                        i += 3
                        break
                    }
                    i += 1
                }
                if i + 2 >= n { i = n }
                continue
            }

            if i + 1 < n && (bytes[i + 1] == 0x21 || bytes[i + 1] == 0x3F) {
                // <!DOCTYPE ...> or <?xml ...>
                i += 2
                while i < n && bytes[i] != 0x3E { i += 1 }
                if i < n { i += 1 }
                continue
            }

            if i + 2 < n && bytes[i + 1] == 0x2F && isAlpha(bytes[i + 2]) {
                // Closing tag </tag>
                i += 2
                let nameStart = i
                while i < n && isTagChar(bytes[i]) { i += 1 }
                let closeName = String(decoding: bytes[nameStart..<i], as: UTF8.self).lowercased()
                while i < n && bytes[i] != 0x3E { i += 1 }
                if i < n { i += 1 }
                var foundIdx: Int?
                for idx in stack.indices.dropFirst().reversed() {
                    let t = stack[idx].tag
                    if t == closeName {
                        foundIdx = idx
                        break
                    }
                    if inlineTags.contains(closeName) && scopeBoundaryTags.contains(t) {
                        break
                    }
                    if closeName == "li" && (t == "ul" || t == "ol" || t == "menu" || t == "div" || t == "section" || t == "body" || t == "html") {
                        break
                    }
                    if (closeName == "dt" || closeName == "dd") && (t == "dl" || t == "div" || t == "section" || t == "body" || t == "html") {
                        break
                    }
                }
                if let matchIdx = foundIdx {
                    stack.removeSubrange(matchIdx..<stack.count)
                }
                continue
            }

            if i + 1 < n && isAlpha(bytes[i + 1]) {
                // Opening tag <tag ...>
                i += 1
                let nameStart = i
                while i < n && isTagChar(bytes[i]) { i += 1 }
                let tagName = String(decoding: bytes[nameStart..<i], as: UTF8.self).lowercased()

                var attrs: [String: String] = [:]
                var selfClosing = false

                while i < n {
                    while i < n && isSpace(bytes[i]) { i += 1 }
                    if i >= n { break }
                    if bytes[i] == 0x3E { // '>'
                        i += 1
                        break
                    }
                    if bytes[i] == 0x2F { // '/'
                        i += 1
                        if i < n && bytes[i] == 0x3E {
                            selfClosing = true
                            i += 1
                            break
                        }
                        continue
                    }

                    // Parse attribute name
                    let attrStart = i
                    while i < n && !isSpace(bytes[i]) && bytes[i] != 0x3D && bytes[i] != 0x3E && bytes[i] != 0x2F {
                        i += 1
                    }
                    let attrName = String(decoding: bytes[attrStart..<i], as: UTF8.self).lowercased()
                    while i < n && isSpace(bytes[i]) { i += 1 }

                    var attrValue = ""
                    if i < n && bytes[i] == 0x3D { // '='
                        i += 1
                        while i < n && isSpace(bytes[i]) { i += 1 }
                        if i < n && (bytes[i] == 0x22 || bytes[i] == 0x27) {
                            let quote = bytes[i]
                            i += 1
                            let valStart = i
                            while i < n && bytes[i] != quote { i += 1 }
                            let rawVal = String(decoding: bytes[valStart..<i], as: UTF8.self)
                            attrValue = HTML4EntityDecoder.decode(rawVal)
                            if i < n { i += 1 }
                        } else {
                            let valStart = i
                            while i < n && !isSpace(bytes[i]) && bytes[i] != 0x3E && !(bytes[i] == 0x2F && i + 1 < n && bytes[i + 1] == 0x3E) {
                                i += 1
                            }
                            let rawVal = String(decoding: bytes[valStart..<i], as: UTF8.self)
                            attrValue = HTML4EntityDecoder.decode(rawVal)
                        }
                    }

                    if !attrName.isEmpty {
                        if attrName == "class" {
                            if let existing = attrs["class"], !existing.isEmpty {
                                attrs["class"] = existing + " " + attrValue
                            } else {
                                attrs["class"] = attrValue
                            }
                        } else if attrs[attrName] == nil {
                            attrs[attrName] = attrValue
                        }
                    }
                }

                // Auto-close implicit tags
                if blockClosePTags.contains(tagName) {
                    for idx in stack.indices.dropFirst().reversed() {
                        let t = stack[idx].tag
                        if t == "p" {
                            stack.removeSubrange(idx..<stack.count)
                            break
                        }
                        if scopeBoundaryTags.contains(t) { break }
                    }
                }
                if tagName == "a" {
                    for idx in stack.indices.dropFirst().reversed() {
                        let t = stack[idx].tag
                        if t == "a" {
                            stack.removeSubrange(idx..<stack.count)
                            break
                        }
                        if scopeBoundaryTags.contains(t) { break }
                    }
                } else if tagName == "li" {
                    for idx in stack.indices.dropFirst().reversed() {
                        let t = stack[idx].tag
                        if t == "ul" || t == "ol" || t == "menu" { break }
                        if t == "li" {
                            stack.removeSubrange(idx..<stack.count)
                            break
                        }
                    }
                } else if tagName == "dt" || tagName == "dd" {
                    for idx in stack.indices.dropFirst().reversed() {
                        let t = stack[idx].tag
                        if t == "dl" { break }
                        if t == "dt" || t == "dd" {
                            stack.removeSubrange(idx..<stack.count)
                            break
                        }
                    }
                } else if tagName == "option" {
                    if stack.last?.tag == "option" {
                        stack.removeLast()
                    }
                }

                let element = PublicHTMLElement(tag: tagName, attributes: attrs, baseUri: baseUri)
                if let parent = stack.last {
                    element.parent = parent
                    parent.children.append(.element(element))
                }

                if !selfClosing && !voidTags.contains(tagName) {
                    if rawTextTags.contains(tagName) {
                        let rawStart = i
                        let targetBytes = Array(tagName.utf8)
                        var rawEnd = n
                        var afterClose = n
                        var cursor = i
                        while cursor + 2 + targetBytes.count <= n {
                            if bytes[cursor] == 0x3C && bytes[cursor + 1] == 0x2F {
                                var matched = true
                                for k in 0..<targetBytes.count {
                                    let b = bytes[cursor + 2 + k]
                                    let lower = (b >= 0x41 && b <= 0x5A) ? (b + 32) : b
                                    if lower != targetBytes[k] {
                                        matched = false
                                        break
                                    }
                                }
                                if matched {
                                    let endTagPos = cursor + 2 + targetBytes.count
                                    if endTagPos < n && (isSpace(bytes[endTagPos]) || bytes[endTagPos] == 0x3E) {
                                        rawEnd = cursor
                                        var closeCursor = endTagPos
                                        while closeCursor < n && bytes[closeCursor] != 0x3E { closeCursor += 1 }
                                        afterClose = closeCursor < n ? closeCursor + 1 : n
                                        break
                                    }
                                }
                            }
                            cursor += 1
                        }
                        let rawContent = String(decoding: bytes[rawStart..<rawEnd], as: UTF8.self)
                        element.rawData = rawContent
                        if tagName == "title" || tagName == "textarea" {
                            element.children.append(.text(HTML4EntityDecoder.decode(rawContent)))
                        }
                        i = afterClose
                    } else {
                        stack.append(element)
                    }
                }
                continue
            }

            // Stray '<'
            appendTextSlice(i, i + 1)
            i += 1
        }

        return PublicHTMLDocument(root: root)
    }
}

private enum PublicCSSParser {
    enum Combinator {
        case root
        case descendant
        case child
    }

    enum AttrOp {
        case exists
        case equals(String)
        case contains(String)
    }

    struct AttrCondition {
        let name: String
        let op: AttrOp
    }

    struct CompoundSelector {
        var tag: String?
        var id: String?
        var classes: [String] = []
        var attrs: [AttrCondition] = []
        var hasSelectors: [[ChainStep]] = []
        var matchesOwnRegexes: [NSRegularExpression] = []
    }

    struct ChainStep {
        let combinator: Combinator
        let selector: CompoundSelector
    }

    static func parseSelectorList(_ css: String) -> [[ChainStep]] {
        let parts = splitTopLevel(css, separator: ",")
        return parts.compactMap { part in
            let chain = parseChain(part)
            return chain.isEmpty ? nil : chain
        }
    }

    private static func splitTopLevel(_ text: String, separator: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var parenDepth = 0
        var bracketDepth = 0
        var quote: Character?
        for ch in text {
            if let q = quote {
                current.append(ch)
                if ch == q { quote = nil }
                continue
            }
            if ch == "\"" || ch == "'" {
                quote = ch
                current.append(ch)
                continue
            }
            if ch == "(" { parenDepth += 1 }
            else if ch == ")" { parenDepth = max(0, parenDepth - 1) }
            else if ch == "[" { bracketDepth += 1 }
            else if ch == "]" { bracketDepth = max(0, bracketDepth - 1) }

            if ch == separator && parenDepth == 0 && bracketDepth == 0 {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(trimmed) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { result.append(trimmed) }
        return result
    }

    private static func parseChain(_ raw: String) -> [ChainStep] {
        var steps: [ChainStep] = []
        let chars = Array(raw)
        let n = chars.count
        var i = 0

        func skipSpaces() {
            while i < n && chars[i].isWhitespace { i += 1 }
        }

        skipSpaces()
        var nextCombinator: Combinator = .root

        while i < n {
            var token = ""
            var parenDepth = 0
            var bracketDepth = 0
            var quote: Character?

            while i < n {
                let ch = chars[i]
                if let q = quote {
                    token.append(ch)
                    if ch == q { quote = nil }
                    i += 1
                    continue
                }
                if ch == "\"" || ch == "'" {
                    quote = ch
                    token.append(ch)
                    i += 1
                    continue
                }
                if ch == "(" { parenDepth += 1 }
                else if ch == ")" { parenDepth = max(0, parenDepth - 1) }
                else if ch == "[" { bracketDepth += 1 }
                else if ch == "]" { bracketDepth = max(0, bracketDepth - 1) }

                if parenDepth == 0 && bracketDepth == 0 && (ch.isWhitespace || ch == ">") {
                    break
                }
                token.append(ch)
                i += 1
            }

            if !token.isEmpty {
                let compound = parseCompound(token)
                steps.append(ChainStep(combinator: steps.isEmpty ? .root : nextCombinator, selector: compound))
            }

            skipSpaces()
            if i < n && chars[i] == ">" {
                nextCombinator = .child
                i += 1
                skipSpaces()
            } else {
                nextCombinator = .descendant
            }
        }
        return steps
    }

    private static func parseCompound(_ token: String) -> CompoundSelector {
        var sel = CompoundSelector()
        let chars = Array(token)
        let n = chars.count
        var i = 0

        func readIdentifier() -> String {
            let start = i
            while i < n {
                let ch = chars[i]
                if ch == "." || ch == "#" || ch == "[" || ch == ":" { break }
                i += 1
            }
            return String(chars[start..<i])
        }

        if i < n && chars[i] != "." && chars[i] != "#" && chars[i] != "[" && chars[i] != ":" {
            let t = readIdentifier().lowercased()
            if !t.isEmpty && t != "*" {
                sel.tag = t
            }
        }

        while i < n {
            let ch = chars[i]
            if ch == "#" {
                i += 1
                let id = readIdentifier()
                if !id.isEmpty { sel.id = id }
            } else if ch == "." {
                i += 1
                let cls = readIdentifier()
                if !cls.isEmpty { sel.classes.append(cls) }
            } else if ch == "[" {
                i += 1
                let start = i
                var quote: Character?
                while i < n {
                    let c = chars[i]
                    if let q = quote {
                        if c == q { quote = nil }
                    } else if c == "\"" || c == "'" {
                        quote = c
                    } else if c == "]" {
                        break
                    }
                    i += 1
                }
                let content = String(chars[start..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
                if i < n && chars[i] == "]" { i += 1 }
                if let range = content.range(of: "*=") {
                    let attrName = content[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let val = unquote(String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
                    sel.attrs.append(AttrCondition(name: attrName, op: .contains(val)))
                } else if let range = content.range(of: "=") {
                    let attrName = content[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let val = unquote(String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
                    sel.attrs.append(AttrCondition(name: attrName, op: .equals(val)))
                } else if !content.isEmpty {
                    sel.attrs.append(AttrCondition(name: content.lowercased(), op: .exists))
                }
            } else if ch == ":" {
                i += 1
                let nameStart = i
                while i < n && chars[i] != "(" { i += 1 }
                let pseudoName = String(chars[nameStart..<i]).lowercased()
                if i < n && chars[i] == "(" {
                    i += 1
                    let argStart = i
                    var depth = 1
                    while i < n && depth > 0 {
                        if chars[i] == "(" { depth += 1 }
                        else if chars[i] == ")" { depth -= 1 }
                        if depth > 0 { i += 1 }
                    }
                    let arg = String(chars[argStart..<i])
                    if i < n && chars[i] == ")" { i += 1 }
                    if pseudoName == "has" {
                        let sub = parseChain(arg)
                        if !sub.isEmpty { sel.hasSelectors.append(sub) }
                    } else if pseudoName == "matchesown" {
                        if let regex = try? NSRegularExpression(pattern: arg, options: []) {
                            sel.matchesOwnRegexes.append(regex)
                        }
                    }
                }
            } else {
                i += 1
            }
        }
        return sel
    }

    private static func unquote(_ s: String) -> String {
        if s.count >= 2 && ((s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'"))) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    static func matchesChain(_ chain: [ChainStep], element: PublicHTMLElement, scopeRoot: PublicHTMLElement) -> Bool {
        guard let last = chain.last, matchesCompound(last.selector, element: element) else { return false }
        if chain.count == 1 { return true }
        return matchAncestors(chain, stepIndex: chain.count - 2, fromConstrainedCombinator: last.combinator, current: element, scopeRoot: scopeRoot)
    }

    private static func matchAncestors(_ chain: [ChainStep], stepIndex: Int, fromConstrainedCombinator combinator: Combinator, current: PublicHTMLElement, scopeRoot: PublicHTMLElement) -> Bool {
        let step = chain[stepIndex]
        switch combinator {
        case .child:
            guard let parent = current.parent, parent.tag != "#document" else { return false }
            guard matchesCompound(step.selector, element: parent) else { return false }
            if stepIndex == 0 { return true }
            return matchAncestors(chain, stepIndex: stepIndex - 1, fromConstrainedCombinator: step.combinator, current: parent, scopeRoot: scopeRoot)
        case .descendant, .root:
            var ancestor = current.parent
            while let anc = ancestor, anc.tag != "#document" {
                if matchesCompound(step.selector, element: anc) {
                    if stepIndex == 0 { return true }
                    if matchAncestors(chain, stepIndex: stepIndex - 1, fromConstrainedCombinator: step.combinator, current: anc, scopeRoot: scopeRoot) {
                        return true
                    }
                }
                if anc === scopeRoot { break }
                ancestor = anc.parent
            }
            return false
        }
    }

    private static func matchesCompound(_ sel: CompoundSelector, element: PublicHTMLElement) -> Bool {
        if let tag = sel.tag, element.tag != tag { return false }
        if let id = sel.id, element.attr("id") != id { return false }
        for cls in sel.classes {
            if !element.hasClass(cls) { return false }
        }
        for cond in sel.attrs {
            switch cond.op {
            case .exists:
                if !element.hasAttr(cond.name) { return false }
            case .equals(let expected):
                if element.attr(cond.name) != expected { return false }
            case .contains(let sub):
                if element.attr(cond.name).range(of: sub, options: .caseInsensitive) == nil { return false }
            }
        }
        for hasChain in sel.hasSelectors {
            if !hasDescendantMatching(hasChain, in: element) { return false }
        }
        for regex in sel.matchesOwnRegexes {
            let own = element.ownText()
            let range = NSRange(own.startIndex..., in: own)
            if regex.firstMatch(in: own, range: range) == nil { return false }
        }
        return true
    }

    private static func hasDescendantMatching(_ chain: [ChainStep], in root: PublicHTMLElement) -> Bool {
        func check(_ node: PublicHTMLElement) -> Bool {
            for child in node.children {
                if case .element(let el) = child {
                    if matchesChain(chain, element: el, scopeRoot: root) || check(el) {
                        return true
                    }
                }
            }
            return false
        }
        return check(root)
    }
}

enum PublicRelaxedJSON {
    static func parse(_ raw: String) throws -> Any {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return obj
        }
        let normalized = normalize(trimmed)
        guard let data = normalized.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw NSError(domain: "PublicRelaxedJSON", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效 JSON"])
        }
        return obj
    }

    static func literal(_ text: String) throws -> String {
        let chars = Array(text)
        guard let first = chars.first, (first == "\"" || first == "'"), chars.count >= 2 else {
            throw NSError(domain: "PublicRelaxedJSON", code: 2, userInfo: [NSLocalizedDescriptionKey: "需要字符串字面量"])
        }
        let quote = first
        var out = ""
        out.reserveCapacity(chars.count)
        var i = 1
        while i < chars.count {
            let ch = chars[i]
            if ch == quote {
                return out
            }
            if ch == "\\" {
                i += 1
                guard i < chars.count else {
                    throw NSError(domain: "PublicRelaxedJSON", code: 3, userInfo: [NSLocalizedDescriptionKey: "字符串格式错误"])
                }
                let esc = chars[i]
                switch esc {
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "\\": out.append("\\")
                case "/": out.append("/")
                case "\"": out.append("\"")
                case "'": out.append("'")
                case "u":
                    guard i + 4 < chars.count,
                          let code = UInt16(String(chars[(i + 1)...(i + 4)]), radix: 16),
                          let scalar = UnicodeScalar(code) else {
                        throw NSError(domain: "PublicRelaxedJSON", code: 3, userInfo: [NSLocalizedDescriptionKey: "字符串格式错误"])
                    }
                    out.unicodeScalars.append(scalar)
                    i += 4
                default:
                    out.append(esc)
                }
            } else {
                out.append(ch)
            }
            i += 1
        }
        throw NSError(domain: "PublicRelaxedJSON", code: 3, userInfo: [NSLocalizedDescriptionKey: "字符串不完整"])
    }

    static func normalize(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count + 32)
        let chars = Array(input)
        var i = 0
        let n = chars.count
        while i < n {
            let c = chars[i]
            if c == "\"" {
                out.append(c)
                i += 1
                while i < n {
                    let sc = chars[i]
                    out.append(sc)
                    i += 1
                    if sc == "\\" && i < n {
                        out.append(chars[i])
                        i += 1
                    } else if sc == "\"" {
                        break
                    }
                }
            } else if c == "'" {
                out.append("\"")
                i += 1
                while i < n {
                    let sc = chars[i]
                    i += 1
                    if sc == "\\" && i < n {
                        let next = chars[i]
                        i += 1
                        if next == "'" {
                            out.append("'")
                        } else {
                            out.append("\\")
                            out.append(next)
                        }
                    } else if sc == "\"" {
                        out.append("\\\"")
                    } else if sc == "'" {
                        out.append("\"")
                        break
                    } else {
                        out.append(sc)
                    }
                }
            } else if c == "{" || c == "," {
                out.append(c)
                i += 1
                while i < n && chars[i].isWhitespace {
                    out.append(chars[i])
                    i += 1
                }
                if i < n && (chars[i].isLetter || chars[i] == "_" || chars[i] == "$") {
                    var j = i
                    while j < n && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "$" || chars[j] == "-") {
                        j += 1
                    }
                    var k = j
                    while k < n && chars[k].isWhitespace { k += 1 }
                    if k < n && chars[k] == ":" {
                        out.append("\"")
                        out.append(String(chars[i..<j]))
                        out.append("\"")
                        i = j
                    }
                }
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }
}
