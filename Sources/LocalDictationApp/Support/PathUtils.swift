import Foundation

extension String {
    /// Expands a leading `~` to the user's home directory.
    var expandingTildeInPath: String {
        NSString(string: self).expandingTildeInPath
    }
}
