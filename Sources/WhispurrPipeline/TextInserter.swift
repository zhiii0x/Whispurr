import Foundation

/// Inserts text into the currently-focused application.
@MainActor public protocol TextInserter: AnyObject {
    func insert(_ text: String)
}
