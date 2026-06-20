import Foundation

public struct DictationContext: Equatable, Sendable {
    public var activeApplicationName: String?
    public var focusedElementDescription: String?
    public var selectedText: String?
    public var visibleText: String?

    public init(
        activeApplicationName: String? = nil,
        focusedElementDescription: String? = nil,
        selectedText: String? = nil,
        visibleText: String? = nil
    ) {
        self.activeApplicationName = activeApplicationName
        self.focusedElementDescription = focusedElementDescription
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
