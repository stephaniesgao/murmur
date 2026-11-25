import Foundation
public enum DictationError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
