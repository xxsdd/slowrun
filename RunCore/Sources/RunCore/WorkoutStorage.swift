import Foundation

public struct WorkoutStorage {
    let directory: URL
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SlowRun", isDirectory: true)
    }
    private var activeURL: URL { directory.appendingPathComponent("active.json") }
    func ensureDirectory() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    public func saveActive(_ engine: WorkoutEngine) throws {
        try ensureDirectory(); try JSONEncoder().encode(engine).write(to: activeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    public func loadActive() throws -> WorkoutEngine? {
        guard FileManager.default.fileExists(atPath: activeURL.path) else { return nil }
        return try JSONDecoder().decode(WorkoutEngine.self, from: Data(contentsOf: activeURL))
    }
    public func clearActive() throws {
        if FileManager.default.fileExists(atPath: activeURL.path) { try FileManager.default.removeItem(at: activeURL) }
    }
    public func save(_ record: WorkoutRecord) throws {
        try ensureDirectory()
        try JSONEncoder().encode(record).write(to: directory.appendingPathComponent("\(record.id.uuidString).json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    public func records() throws -> [WorkoutRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "active.json" }
            .compactMap { try? JSONDecoder().decode(WorkoutRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }
    public func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent("\(id.uuidString).json"))
    }
}
