import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool {
        trimmed.isEmpty
    }

    func trimmedOr(_ fallback: String) -> String {
        let value = trimmed
        return value.isEmpty ? fallback : value
    }
}
