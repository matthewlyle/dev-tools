import Foundation

enum ValueFormatter {
    static func display(_ attribute: Attribute) -> String? {
        let name = attribute.name
        let value = attribute.value

        if name.hasSuffix("At"), name != "originallyAvailableAt", let epoch = TimeInterval(value), epoch > 1_000_000_000 {
            return Date(timeIntervalSince1970: epoch).formatted(date: .abbreviated, time: .shortened)
        }
        if name == "duration" || name.hasSuffix("Offset"), let ms = Int(value), ms >= 1000 {
            return Duration.milliseconds(ms).formatted(.time(pattern: ms >= 3_600_000 ? .hourMinuteSecond : .minuteSecond))
        }
        if name == "size", let bytes = Int64(value), bytes > 100_000 {
            return bytes.formatted(.byteCount(style: .file))
        }
        if name == "bitrate", let kbps = Int(value) {
            return kbps >= 1000 ? String(format: "%.1f Mbps", Double(kbps) / 1000) : "\(kbps) kbps"
        }
        return nil
    }
}
