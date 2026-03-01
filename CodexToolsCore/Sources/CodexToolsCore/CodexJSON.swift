import Foundation

public enum CodexJSON {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(CodexDateCoding.encode(date))
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                return try CodexDateCoding.decode(string)
            }
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date value"
            )
        }
        return decoder
    }
}

public enum CodexDateCoding {
    public static func encode(_ date: Date) -> String {
        CodexDateFormatters.lock.lock()
        defer { CodexDateFormatters.lock.unlock() }
        return CodexDateFormatters.encodeFractional.string(from: date)
    }

    public static func decode(_ value: String) throws -> Date {
        CodexDateFormatters.lock.lock()
        defer { CodexDateFormatters.lock.unlock() }

        if let date = CodexDateFormatters.decodeFractional.date(from: value) {
            return date
        }

        if let date = CodexDateFormatters.decodePlain.date(from: value) {
            return date
        }

        if let date = CodexDateFormatters.decodeFallback.date(from: value) {
            return date
        }

        throw NSError(
            domain: "CodexDateCoding",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid date format: \(value)"]
        )
    }
}

private enum CodexDateFormatters {
    static let lock = NSLock()

    nonisolated(unsafe) static let encodeFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    nonisolated(unsafe) static let decodeFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    nonisolated(unsafe) static let decodePlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static let decodeFallback: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter
    }()
}
