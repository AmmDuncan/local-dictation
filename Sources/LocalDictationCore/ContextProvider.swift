import Foundation

public struct DictationContext: Equatable, Sendable {
    public var activeApplicationName: String?
    public var focusedElementDescription: String?
    /// The text immediately before the caret (current line / preceding ~120
    /// chars) — the highest-proximity signal for what the user is about to
    /// dictate, e.g. `git push origin ` right before they say a branch name.
    public var precedingText: String?
    public var selectedText: String?
    public var visibleText: String?

    public init(
        activeApplicationName: String? = nil,
        focusedElementDescription: String? = nil,
        precedingText: String? = nil,
        selectedText: String? = nil,
        visibleText: String? = nil
    ) {
        self.activeApplicationName = activeApplicationName
        self.focusedElementDescription = focusedElementDescription
        self.precedingText = precedingText
        self.selectedText = selectedText
        self.visibleText = visibleText
    }
}

public protocol ContextProvider: Sendable {
    func currentContext() async -> DictationContext
}

public struct EmptyContextProvider: ContextProvider {
    public init() {}

    public func currentContext() async -> DictationContext {
        DictationContext()
    }
}
