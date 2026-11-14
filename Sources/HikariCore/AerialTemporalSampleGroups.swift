import Foundation

/// Bounded MOV metadata inspection; media payloads are never loaded into memory.
/// Require both descriptions and mappings, rather than finding strings in mdat.
public enum AerialTemporalSampleGroups {
    public static func isPresent(in url: URL) throws -> Bool {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let end = try file.seekToEnd()
        var offset: UInt64 = 0
        while offset <= end, end - offset >= 8 {
            try file.seek(toOffset: offset)
            guard let header = try file.read(upToCount: 8), header.count == 8 else { return false }
            var size = integer(header, 0, 4), headerSize: UInt64 = 8
            if size == 1 {
                guard let large = try file.read(upToCount: 8), large.count == 8 else { return false }
                size = integer(large, 0, 8); headerSize = 16
            } else if size == 0 { size = end - offset }
            guard size >= headerSize, size <= end - offset else { return false }
            if String(data: header[4..<8], encoding: .ascii) == "moov" {
                guard size - headerSize <= 64 * 1024 * 1024,
                      let metadata = try file.read(upToCount: Int(size - headerSize)),
                      metadata.count == Int(size - headerSize) else { return false }
                var descriptions = Set<String>(), mappings = Set<String>()
                guard inspect(metadata, start: 0, end: metadata.count, depth: 0,
                              descriptions: &descriptions, mappings: &mappings) else { return false }
                return Set(["tscl", "tsas"]).isSubset(of: descriptions.intersection(mappings))
            }
            offset += size
        }
        return false
    }
    private static func integer(_ data: Data, _ offset: Int, _ count: Int) -> UInt64 {
        data[offset..<(offset + count)].reduce(0) { ($0 << 8) | UInt64($1) }
    }
    private static func inspect(_ data: Data, start: Int, end: Int, depth: Int,
                                descriptions: inout Set<String>, mappings: inout Set<String>) -> Bool {
        guard depth <= 8 else { return false }
        var offset = start
        while offset < end {
            guard end - offset >= 8 else { return false }
            var length = integer(data, offset, 4), header = 8
            let type = String(data: data[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            if length == 1 {
                guard end - offset >= 16 else { return false }
                length = integer(data, offset + 8, 8); header = 16
            } else if length == 0 { length = UInt64(end - offset) }
            guard length >= header, length <= UInt64(end - offset) else { return false }
            let body = offset + header, next = offset + Int(length)
            if ["sgpd", "sbgp", "csgm"].contains(type) {
                guard next - body >= 8,
                      let group = String(data: data[(body + 4)..<(body + 8)], encoding: .ascii) else { return false }
                if type == "sgpd" { descriptions.insert(group) } else { mappings.insert(group) }
            } else if ["trak", "mdia", "minf", "stbl"].contains(type) {
                guard inspect(data, start: body, end: next, depth: depth + 1,
                              descriptions: &descriptions, mappings: &mappings) else { return false }
            }
            offset = next
        }
        return true
    }
}
