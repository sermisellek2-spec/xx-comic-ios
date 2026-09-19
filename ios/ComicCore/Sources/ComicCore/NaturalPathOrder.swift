import Foundation

/// Matches Android's component/chunk order, including arbitrary-length page numbers.
public enum NaturalPathOrder {
    public static func less(_ lhs: String, _ rhs: String) -> Bool {
        func normalize(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        let a = normalize(lhs), b = normalize(rhs)
        let pathsA = a.split(separator: "/", omittingEmptySubsequences: false)
        let pathsB = b.split(separator: "/", omittingEmptySubsequences: false)
        for (left, right) in zip(pathsA, pathsB) {
            let order = segment(Array(left.utf16), Array(right.utf16))
            if order != 0 { return order < 0 }
        }
        if pathsA.count != pathsB.count { return pathsA.count < pathsB.count }
        let insensitive = text(Array(a.utf16), Array(b.utf16), ignoreCase: true)
        return insensitive != 0 ? insensitive < 0 : text(Array(a.utf16), Array(b.utf16), ignoreCase: false) < 0
    }
    private static func digit(_ unit: UInt16) -> Int? {
        guard let scalar = UnicodeScalar(unit), scalar.properties.numericType == .decimal,
              let value = scalar.properties.numericValue else { return nil }
        return Int(value)
    }
    private static func chunks(_ units: [UInt16]) -> [[UInt16]] {
        var result: [[UInt16]] = []
        for unit in units {
            if let last = result.last?.last, (digit(last) != nil) == (digit(unit) != nil) {
                result[result.count - 1].append(unit)
            } else { result.append([unit]) }
        }
        return result
    }
    private static func segment(_ a: [UInt16], _ b: [UInt16]) -> Int {
        let left = chunks(a), right = chunks(b)
        for (x, y) in zip(left, right) {
            let numericX = x.first.flatMap(digit) != nil, numericY = y.first.flatMap(digit) != nil
            if numericX && numericY {
                let nx = Array(x.compactMap(digit).drop(while: { $0 == 0 }))
                let ny = Array(y.compactMap(digit).drop(while: { $0 == 0 }))
                if nx.count != ny.count { return nx.count < ny.count ? -1 : 1 }
                if nx != ny { return nx.lexicographicallyPrecedes(ny) ? -1 : 1 }
                if x.count != y.count { return x.count < y.count ? -1 : 1 }
            } else if numericX != numericY { return numericX ? -1 : 1 }
            else {
                let insensitive = text(x, y, ignoreCase: true)
                if insensitive != 0 { return insensitive }
                let sensitive = text(x, y, ignoreCase: false)
                if sensitive != 0 { return sensitive }
            }
        }
        return left.count == right.count ? 0 : (left.count < right.count ? -1 : 1)
    }
    private static func text(_ a: [UInt16], _ b: [UInt16], ignoreCase: Bool) -> Int {
        func mapped(_ unit: UInt16, upper: Bool) -> UInt16 {
            guard let scalar = UnicodeScalar(unit) else { return unit }
            let value = upper ? String(scalar).uppercased() : String(scalar).lowercased()
            return value.utf16.count == 1 ? value.utf16.first! : unit
        }
        for (x, y) in zip(a, b) where x != y {
            var left = x, right = y
            if ignoreCase {
                left = mapped(left, upper: true); right = mapped(right, upper: true)
                if left == right { continue }
                left = mapped(left, upper: false); right = mapped(right, upper: false)
            }
            if left != right { return left < right ? -1 : 1 }
        }
        return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
    }
}
