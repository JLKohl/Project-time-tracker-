import Foundation

/// Where tracker data is loaded from and saved to.
public protocol TrackerStore {
    func load() throws -> TrackerData
    func save(_ data: TrackerData) throws
}

/// Saves data as a JSON file, by default in
/// `~/Library/Application Support/ProjectTimeTracker/data.json`.
public final class JSONFileStore: TrackerStore {
    public let fileURL: URL

    public init(fileURL: URL = JSONFileStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("ProjectTimeTracker", isDirectory: true)
            .appendingPathComponent("data.json")
    }

    public func load() throws -> TrackerData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return TrackerData()
        }
        let raw = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(TrackerData.self, from: raw)
    }

    public func save(_ data: TrackerData) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let raw = try Self.encoder.encode(data)
        // Atomic so a crash mid-write never leaves a half-written file.
        try raw.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Keeps data in memory only. Used by tests and previews.
public final class InMemoryStore: TrackerStore {
    public private(set) var data: TrackerData
    public private(set) var saveCount = 0

    public init(data: TrackerData = TrackerData()) {
        self.data = data
    }

    public func load() throws -> TrackerData { data }

    public func save(_ data: TrackerData) throws {
        self.data = data
        saveCount += 1
    }
}
