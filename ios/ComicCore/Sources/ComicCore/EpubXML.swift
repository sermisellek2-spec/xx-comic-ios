import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A bounded XML tree shared by container, OPF and navigation parsing. No network/entity resolution.
enum EpubXML {
    final class Node {
        enum Content { case text(String), child(Node) }
        let name: String
        let qualifiedName: String
        let attributes: [String: String]
        var children: [Node] = []
        var content: [Content] = []
        init(_ name: String, _ attributes: [String: String] = [:], qualifiedName: String? = nil) {
            self.name = name; self.attributes = attributes; self.qualifiedName = qualifiedName ?? name
        }
        subscript(_ attribute: String) -> String { attributes[attribute] ?? "" }
        var text: String {
            content.map { part in
                switch part { case .text(let string): return string; case .child(let node): return node.text }
            }.joined()
        }
        func descendants(_ name: String) -> [Node] {
            children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
        }
    }

    static func parse(_ data: Data, path: String) throws -> Node {
        try Task.checkCancellation()
        // Removing zero bytes exposes ASCII declarations in UTF-8/16/32, with or without BOM.
        // Reject DTDs entirely before handing any bytes to libxml2/FoundationXML.
        let declarations = String(decoding: data.filter { $0 != 0 }, as: UTF8.self).uppercased()
        guard !declarations.contains("<!DOCTYPE"), !declarations.contains("<!ENTITY") else { throw EpubError.unsafeXML }
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate
        let success = parser.parse()
        if let error = delegate.failure { throw error }
        try Task.checkCancellation()
        guard success, parser.parserError == nil, delegate.document.children.count == 1 else { throw EpubError.invalidXML(path) }
        return delegate.document
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let document = Node("#document")
        var stack: [Node] = []
        var nodes = 0
        var failure: Error?
        override init() { super.init(); stack = [document] }

        private func check(_ parser: XMLParser) -> Bool {
            do { try Task.checkCancellation(); return failure == nil }
            catch { failure = error; parser.abortParsing(); return false }
        }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            guard check(parser) else { return }
            nodes += 1
            guard nodes <= 100_000, stack.count <= 128 else {
                failure = EpubError.limitExceeded("XML 节点超过 100000 或嵌套超过 128 层")
                parser.abortParsing(); return
            }
            let node = Node(elementName, attributes, qualifiedName: qualifiedName)
            stack.last?.children.append(node)
            stack.last?.content.append(.child(node))
            stack.append(node)
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            guard check(parser), stack.count > 1 else { return }
            stack.removeLast()
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard check(parser) else { return }
            stack.last?.content.append(.text(string))
        }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard check(parser) else { return }
            stack.last?.content.append(.text(String(decoding: CDATABlock, as: UTF8.self)))
        }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
            failure = EpubError.unsafeXML; parser.abortParsing(); return nil
        }
    }
}
