import Foundation

/// A verified implementation must retain its browser network context, not just copy cookies.
public protocol ComicBrowserSession: Sendable {
    func fetch(_ url: URL) async throws -> String
    func fetchInteractive(_ url: URL) async throws -> String
}
