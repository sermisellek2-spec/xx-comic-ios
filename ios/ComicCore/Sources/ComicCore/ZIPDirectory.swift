import Foundation

/// ZIPFoundation's iterator can stop silently. Validate record boundaries/counts and flags
/// before using it; compression and ZIP entry decoding remain ZIPFoundation's responsibility.
struct ZIPDirectory {
    struct Record {
        let utf8: Bool
        let size: UInt64
        let compressedSize: UInt64
        let checksum: UInt32
        let dataOffset: UInt64
    }
    let records: [Record]

    init(url: URL) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let length = try input.seekToEnd()
        func read(_ offset: UInt64, _ count: Int) throws -> Data {
            try Task.checkCancellation()
            guard offset <= length, UInt64(count) <= length - offset else { throw LocalLibraryError.invalidArchive }
            if count == 0 { return Data() }
            try input.seek(toOffset: offset)
            guard let data = try input.read(upToCount: count), data.count == count else { throw LocalLibraryError.invalidArchive }
            return data
        }
        guard length >= 22 else { throw LocalLibraryError.invalidArchive }
        let tailSize = Int(min(length, 65_557)), tailOffset = length - UInt64(tailSize)
        let tail = try read(tailOffset, tailSize)
        guard let end = stride(from: tailSize - 22, through: 0, by: -1).first(where: {
            tail.number($0, 4) == 0x06054b50 && $0 + 22 + Int(tail.number($0 + 20, 2)) == tailSize
        }) else { throw LocalLibraryError.invalidArchive }
        guard tail.number(end + 4, 2) == 0, tail.number(end + 6, 2) == 0,
              tail.number(end + 8, 2) == tail.number(end + 10, 2) else { throw LocalLibraryError.invalidArchive }
        var count = tail.number(end + 10, 2), size = tail.number(end + 12, 4), start = tail.number(end + 16, 4)
        var directoryEnd = tailOffset + UInt64(end)
        if count == 0xffff || size == 0xffffffff || start == 0xffffffff {
            guard directoryEnd >= 20 else { throw LocalLibraryError.invalidArchive }
            let locator = try read(directoryEnd - 20, 20)
            guard locator.number(0, 4) == 0x07064b50, locator.number(4, 4) == 0, locator.number(16, 4) == 1 else { throw LocalLibraryError.invalidArchive }
            let recordOffset = locator.number(8, 8), record = try read(recordOffset, 56)
            let recordSize = record.number(4, 8)
            guard record.number(0, 4) == 0x06064b50, recordSize >= 44, recordOffset <= directoryEnd - 20,
                  recordSize <= directoryEnd - 20 - recordOffset, recordSize + 12 == directoryEnd - 20 - recordOffset,
                  record.number(16, 4) == 0, record.number(20, 4) == 0,
                  record.number(24, 8) == record.number(32, 8) else { throw LocalLibraryError.invalidArchive }
            count = record.number(32, 8); size = record.number(40, 8); start = record.number(48, 8)
            directoryEnd = recordOffset
        }
        guard count <= 50_000 else { throw LocalLibraryError.archiveTooLarge }
        guard start <= directoryEnd, size == directoryEnd - start else { throw LocalLibraryError.invalidArchive }
        var offset = start, records: [Record] = [], total: UInt64 = 0
        for _ in 0..<count {
            guard offset <= directoryEnd, directoryEnd - offset >= 46 else { throw LocalLibraryError.invalidArchive }
            let header = try read(offset, 46), flags = header.number(8, 2), method = header.number(10, 2)
            guard header.number(0, 4) == 0x02014b50, flags & 0x2041 == 0,
                  method == 0 || method == 8, header.number(34, 2) == 0 else { throw LocalLibraryError.invalidArchive }
            let nameLength = Int(header.number(28, 2)), extraLength = Int(header.number(30, 2))
            let variableLength = nameLength + extraLength + Int(header.number(32, 2))
            guard UInt64(variableLength) <= directoryEnd - offset - 46 else { throw LocalLibraryError.invalidArchive }
            let variable = try read(offset + 46, variableLength)
            let values = try variable.subdata(in: nameLength..<nameLength + extraLength)
                .zip64Values([header.number(24, 4), header.number(20, 4), header.number(42, 4)])
            let unpacked = values[0], packed = values[1], localOffset = values[2]
            guard unpacked <= UInt64(LocalLibrary.maximumImageBytes), unpacked <= UInt64(LocalLibrary.maximumImportBytes) - total else { throw LocalLibraryError.archiveTooLarge }
            total += unpacked
            guard localOffset <= start, start - localOffset >= 30 else { throw LocalLibraryError.invalidArchive }
            let local = try read(localOffset, 30)
            guard local.number(0, 4) == 0x04034b50, local.number(6, 2) == flags, local.number(8, 2) == method,
                  local.number(26, 2) == UInt64(nameLength) else { throw LocalLibraryError.invalidArchive }
            let dataOffset = localOffset + 30 + local.number(26, 2) + local.number(28, 2)
            guard dataOffset <= start, packed <= start - dataOffset,
                  try read(localOffset + 30, nameLength) == variable.prefix(nameLength) else { throw LocalLibraryError.invalidArchive }
            if flags & 8 == 0 {
                let localValues = try read(localOffset + 30 + UInt64(nameLength), Int(local.number(28, 2)))
                    .zip64Values([local.number(22, 4), local.number(18, 4)])
                guard local.number(14, 4) == header.number(16, 4), localValues == [unpacked, packed] else { throw LocalLibraryError.invalidArchive }
            }
            if method == 0 && packed != unpacked { throw LocalLibraryError.invalidArchive }
            records.append(Record(utf8: flags & 0x800 != 0, size: unpacked, compressedSize: packed, checksum: UInt32(header.number(16, 4)), dataOffset: dataOffset))
            offset += 46 + UInt64(variableLength)
        }
        guard offset == directoryEnd else { throw LocalLibraryError.invalidArchive }
        self.records = records
    }
}

private extension Data {
    func zip64Values(_ values: [UInt64]) throws -> [UInt64] {
        guard values.contains(0xffffffff) else { return values }
        var cursor = 0
        while cursor + 4 <= count {
            let size = Int(number(cursor + 2, 2))
            guard size <= count - cursor - 4 else { throw LocalLibraryError.invalidArchive }
            if number(cursor, 2) == 1 {
                let end = cursor + 4 + size
                cursor += 4
                return try values.map { value in
                    guard value == 0xffffffff else { return value }
                    guard cursor + 8 <= end else { throw LocalLibraryError.invalidArchive }
                    defer { cursor += 8 }
                    return number(cursor, 8)
                }
            }
            cursor += 4 + size
        }
        throw LocalLibraryError.invalidArchive
    }
    func number(_ offset: Int, _ size: Int) -> UInt64 {
        (0..<size).reduce(0) { $0 | UInt64(self[offset + $1]) << ($1 * 8) }
    }
}
