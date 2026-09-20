import Foundation

public enum PalmDoc {
    private struct InvalidData: LocalizedError {
        let errorDescription: String?
        init(_ reason: String) { errorDescription = reason }
    }

    /// Join text records (at most 16 MiB) before decoding so backreferences share one dictionary.
    public static func decompress(_ input: Data, maximumOutputBytes: Int = 8 * 1024 * 1024) throws -> Data {
        try Task.checkCancellation()
        guard maximumOutputBytes > 0 else { return Data() }
        guard input.count <= 16 * 1024 * 1024 else { throw InvalidData("PalmDOC 记录过大") }
        let limit = min(maximumOutputBytes, 8 * 1024 * 1024)
        return try input.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var output = Data(), position = 0, nextCancellation = 0
            while position < bytes.count && output.count < limit {
                if position >= nextCancellation {
                    try Task.checkCancellation()
                    nextCancellation = position + 4096
                }
                let byte = bytes[position]
                position += 1
                switch byte {
                case 0, 9...127:
                    output.append(byte)
                case 1...8:
                    let count = Int(byte)
                    guard count <= bytes.count - position else { throw InvalidData("PalmDOC 字面量记录截断") }
                    let copied = min(count, limit - output.count)
                    output.append(contentsOf: bytes[position..<position + copied])
                    position += count
                case 128...191:
                    guard position < bytes.count else { throw InvalidData("PalmDOC 回溯记录截断") }
                    let compound = Int(byte & 0x3F) << 8 | Int(bytes[position])
                    position += 1
                    let distance = compound >> 3, length = (compound & 7) + 3
                    guard distance > 0, distance <= output.count else { throw InvalidData("PalmDOC 回溯距离无效") }
                    for _ in 0..<min(length, limit - output.count) {
                        // Re-evaluate the source index after each append to allow overlap.
                        output.append(output[output.count - distance])
                    }
                default:
                    output.append(32)
                    if output.count < limit { output.append(byte ^ 0x80) }
                }
            }
            try Task.checkCancellation()
            return output
        }
    }
}
