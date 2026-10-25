import XCTest
@testable import RunCore

final class WorkoutStorageTests: XCTestCase {
    func testDeletingOneRecordPreservesOtherRecordsAndActiveWorkout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = WorkoutStorage(directory: directory)
        var first = WorkoutEngine(plan: .threeK)
        var second = WorkoutEngine(plan: .fiveK)
        let active = WorkoutEngine(plan: .beginner)
        _ = first.finish(at: Date()); _ = second.finish(at: Date())
        try storage.save(first.record); try storage.save(second.record); try storage.saveActive(active)
        try storage.delete(first.record.id)
        XCTAssertEqual(try storage.records().map(\.id), [second.record.id])
        XCTAssertEqual(try storage.loadActive()?.record.id, active.record.id)
        XCTAssertThrowsError(try storage.delete(first.record.id))
        XCTAssertEqual(try storage.records().map(\.id), [second.record.id])
        XCTAssertEqual(try storage.loadActive()?.record.id, active.record.id)
    }
}
