import Foundation

/// Coordinates the user's current snapshot-persistence preference across
/// asynchronous capture, write, and removal operations.
public final class WallpaperSnapshotLifecycle: @unchecked Sendable {
    public struct Token: Equatable, Sendable {
        fileprivate let revision: UInt64
    }

    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var persistenceEnabled: Bool

    public init(persistenceEnabled: Bool = true) {
        self.persistenceEnabled = persistenceEnabled
    }

    /// Returns a token for the latest preference. A real transition advances
    /// the revision, invalidating work that was queued under the previous one.
    @discardableResult
    public func transition(to enabled: Bool) -> Token {
        lock.lock()
        defer { lock.unlock() }
        if persistenceEnabled != enabled {
            persistenceEnabled = enabled
            revision &+= 1
        }
        return Token(revision: revision)
    }

    public func currentToken() -> Token {
        lock.lock()
        defer { lock.unlock() }
        return Token(revision: revision)
    }

    public func permitsPersistence(using token: Token) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return persistenceEnabled && token.revision == revision
    }

    public func permitsRemoval(using token: Token) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !persistenceEnabled && token.revision == revision
    }
}
