import Foundation
import ComicZlib

/// System zlib supplies DEFLATE; this adapter bounds input and requires complete stream consumption.
/// ZIPFoundation 0.9.20's Linux decoder does not enforce the compressed input length.
enum ZIPDeflate {
    static func extract(url: URL, offset: UInt64, compressedSize: UInt64, consumer: (Data) throws -> Void) throws -> UInt32 {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        try input.seek(toOffset: offset)
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw LocalLibraryError.invalidArchive }
        defer { inflateEnd(&stream) }
        let chunkSize = 256 * 1024
        var remaining = compressedSize, checksum = crc32(0, nil, 0)
        var output = [UInt8](repeating: 0, count: chunkSize)
        while remaining > 0 {
            try Task.checkCancellation()
            let count = Int(min(UInt64(chunkSize), remaining))
            guard let chunk = try input.read(upToCount: count), chunk.count == count else { throw LocalLibraryError.invalidArchive }
            remaining -= UInt64(count)
            let ended = try chunk.withUnsafeBytes { source -> Bool in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: UInt8.self).baseAddress)
                stream.avail_in = UInt32(chunk.count)
                repeat {
                    try Task.checkCancellation()
                    let before = stream.avail_in
                    let result = output.withUnsafeMutableBytes { destination -> Int32 in
                        stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress
                        stream.avail_out = UInt32(chunkSize)
                        return inflate(&stream, Z_NO_FLUSH)
                    }
                    let produced = chunkSize - Int(stream.avail_out)
                    // A full output buffer can need one extra call before requesting more input.
                    if result == Z_BUF_ERROR && before == 0 && produced == 0 && remaining > 0 { return false }
                    guard result == Z_OK || result == Z_STREAM_END else { throw LocalLibraryError.invalidArchive }
                    if produced > 0 {
                        let data = Data(output.prefix(produced))
                        try consumer(data)
                        checksum = data.withUnsafeBytes { crc32(checksum, $0.bindMemory(to: UInt8.self).baseAddress, UInt32(produced)) }
                    }
                    if result == Z_STREAM_END {
                        guard stream.avail_in == 0, remaining == 0 else { throw LocalLibraryError.invalidArchive }
                        return true
                    }
                    guard produced > 0 || stream.avail_in < before else { throw LocalLibraryError.invalidArchive }
                } while stream.avail_in > 0 || stream.avail_out == 0
                return false
            }
            if ended { return UInt32(checksum) }
        }
        throw LocalLibraryError.invalidArchive
    }
}
