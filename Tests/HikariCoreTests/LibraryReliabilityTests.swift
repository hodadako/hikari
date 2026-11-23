import Foundation
import XCTest
@testable import HikariCore

final class LibraryReliabilityTests: XCTestCase {
    private var root: URL!
    private var container: SharedContainer!
    private var store: ContentStore!
    private let files = FileManager.default

    override func setUpWithError() throws {
        root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        container = try SharedContainer(rootURL: root)
        store = ContentStore(container: container)
    }

    override func tearDownWithError() throws {
        try files.removeItem(at: root)
    }

    private func makeItem(_ name: String, bytes: String = "abc") throws -> LiveContent {
        let item = LiveContent(title: name, relativePath: "Media/\(name).mov", fileSize: Int64(bytes.utf8.count),
                               duration: 1, width: 10, height: 10, codec: nil, thumbnailRelativePath: nil)
        try Data(bytes.utf8).write(to: container.mediaURL(for: item))
        return item
    }

    func testMissingAndDamagedIndexesHaveDifferentOutcomes() throws {
        XCTAssertTrue(try store.load().isEmpty)
        let damaged = Data("[{".utf8)
        try damaged.write(to: container.contentsURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: container.contentsURL), damaged)
    }

    func testIndexWriteFailureKeepsManagedMediaEvenAfterRecovery() throws {
        let item = try makeItem("keep")
        try store.save([item])
        let backup = root.appendingPathComponent("saved-index")
        try files.moveItem(at: container.contentsURL, to: backup)
        try files.createDirectory(at: container.contentsURL, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.delete(item, from: [item]))
        XCTAssertTrue(files.fileExists(atPath: container.mediaURL(for: item).path))
        try files.removeItem(at: container.contentsURL)
        try files.moveItem(at: backup, to: container.contentsURL)
        XCTAssertEqual(try store.load().map(\.id), [item.id])
        XCTAssertTrue(files.fileExists(atPath: container.mediaURL(for: item).path))
    }

    func testCommittedDeletionRetriesCleanupOnReopenAndPreservesOtherFiles() throws {
        let item = try makeItem("delete")
        let kept = try makeItem("keep")
        try store.save([item, kept])
        // Recreate the on-disk boundary immediately after the index commits.
        let pending = root.appendingPathComponent("PendingDeletions", isDirectory: true)
        try files.createDirectory(at: pending, withIntermediateDirectories: false)
        let marker = pending.appendingPathComponent(item.id.uuidString + ".json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(item).write(to: marker)
        try store.save([kept])
        XCTAssertEqual(try store.load().map(\.id), [kept.id])
        XCTAssertFalse(files.fileExists(atPath: container.mediaURL(for: item).path))
        XCTAssertTrue(files.fileExists(atPath: container.mediaURL(for: kept).path))
        XCTAssertFalse(files.fileExists(atPath: marker.path))
        XCTAssertEqual(try store.load().map(\.id), [kept.id])
    }

    func testDuplicateCheckFiltersSizeAndReusesLegacyHashesAcrossLaunches() throws {
        let large = try makeItem("large", bytes: "different size")
        let small = try makeItem("small")
        let contents = [large, small]
        var index = VideoHashIndex(container: container, contents: contents)
        let smallURL = container.mediaURL(for: small)
        var reads: [URL] = []
        let hash: (URL) throws -> String = { url in
            reads.append(url)
            return String(decoding: try Data(contentsOf: url), as: UTF8.self)
        }
        XCTAssertTrue(index.containsDuplicate(ofSize: 3, sha256: "abc", in: contents, hashFile: hash))
        XCTAssertEqual(reads, [smallURL])
        index.persistChanges()
        reads.removeAll()
        index = VideoHashIndex(container: container, contents: contents)
        XCTAssertTrue(index.containsDuplicate(ofSize: 3, sha256: "abc", in: contents, hashFile: hash))
        XCTAssertTrue(reads.isEmpty)
        try Data("xyz".utf8).write(to: smallURL, options: .atomic)
        XCTAssertFalse(index.containsDuplicate(ofSize: 3, sha256: "abc", in: contents, hashFile: hash))
        XCTAssertTrue(index.containsDuplicate(ofSize: 3, sha256: "xyz", in: contents, hashFile: hash))
        XCTAssertEqual(reads, [smallURL])
    }

    func testDeferredApplyConsumesOnlyTheLatestSelectionOnce() {
        let first = UUID()
        let latest = UUID()
        var queue = NativeLockSelectionQueue()
        queue.deferSelection(first)
        queue.deferSelection(latest)
        XCTAssertFalse(queue.takeIfReady(currentID: latest, available: false))
        XCTAssertTrue(queue.takeIfReady(currentID: latest, available: true))
        XCTAssertFalse(queue.takeIfReady(currentID: latest, available: true))
        queue.deferSelection(first)
        XCTAssertFalse(queue.takeIfReady(currentID: latest, available: true))
        queue.deferSelection(latest)
        queue.cancel()
        XCTAssertFalse(queue.takeIfReady(currentID: latest, available: true))
    }

    func testImporterRejectsDuplicateBeforeCopyingLegacyMedia() async throws {
        let item = try makeItem("legacy")
        let source = root.appendingPathComponent("another-name.mov")
        try files.copyItem(at: container.mediaURL(for: item), to: source)
        for _ in 0..<2 {
            do {
                _ = try await VideoImporter(container: container).importVideo(from: source, existingContents: [item])
                XCTFail("Expected the importer to reject duplicate content")
            } catch {
                XCTAssertEqual(error as? HikariError, .duplicateContent)
            }
        }
        let managed = try files.contentsOfDirectory(atPath: container.mediaDirectoryURL.path)
        XCTAssertEqual(managed, ["legacy.mov"])
    }
}
