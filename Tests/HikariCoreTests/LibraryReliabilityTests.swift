import CryptoKit
import Foundation
import ImageIO
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

    func testSuccessfulImportPersistsManagedVideoAndThumbnailAcrossReopen() async throws {
        let source = root.appendingPathComponent("holiday.mov")
        try await TestVideo.write(to: source)
        let original = try Data(contentsOf: source)
        let item = try await VideoImporter(container: container).importVideo(from: source, existingContents: [])
        try store.save([item])
        try files.removeItem(at: source)

        let reopened = try ContentStore(container: container).load()
        let saved = try XCTUnwrap(reopened.first)
        XCTAssertEqual(reopened.map(\.id), [item.id])
        XCTAssertEqual(saved.title, "holiday")
        XCTAssertEqual(saved.fileSize, Int64(original.count))
        XCTAssertEqual(saved.width, 64)
        XCTAssertEqual(saved.height, 64)
        XCTAssertEqual(saved.codec, "avc1")
        XCTAssertGreaterThan(saved.duration, 0)
        let managedURL = container.mediaURL(for: saved)
        XCTAssertEqual(try Data(contentsOf: managedURL), original)
        let thumbnail = try XCTUnwrap(container.thumbnailURL(for: saved))
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(thumbnail as CFURL, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(image, 0, nil))

        var hashes = VideoHashIndex(container: container, contents: reopened)
        // A freshly imported video's digest should survive a restart without rereading the video.
        let digest = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        var reads: [URL] = []
        let hashFile: (URL) throws -> String = { url in
            reads.append(url)
            return SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        XCTAssertTrue(hashes.containsDuplicate(ofSize: saved.fileSize, sha256: digest, in: reopened, hashFile: hashFile))
        XCTAssertTrue(reads.isEmpty)

        // Replacing the managed file must invalidate the imported digest, even at the same size.
        var replacement = original
        replacement[0] ^= 1
        try replacement.write(to: managedURL, options: .atomic)
        XCTAssertFalse(hashes.containsDuplicate(ofSize: saved.fileSize, sha256: digest, in: reopened, hashFile: hashFile))
        XCTAssertEqual(reads, [managedURL])
    }

    func testFailedMoveRemovesStagedCopyAndPreservesOriginal() async throws {
        let source = root.appendingPathComponent("holiday.mov")
        try await TestVideo.write(to: source)
        let original = try Data(contentsOf: source)
        let importer = VideoImporter(container: container, fileManager: FailingMove())

        do {
            _ = try await importer.importVideo(from: source, existingContents: [])
            XCTFail("The final move should have failed")
        } catch HikariError.fileCopyFailed { }

        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try files.contentsOfDirectory(atPath: container.mediaDirectoryURL.path), [])
        XCTAssertEqual(try files.contentsOfDirectory(atPath: container.thumbnailsDirectoryURL.path), [])
    }

    func testImporterChecksTheBytesCopiedEvenWhenTheSourceStampIsUnchanged() async throws {
        let source = root.appendingPathComponent("source.mov")
        try await TestVideo.write(to: source)
        let existing = try makeItem("existing")
        let existingURL = container.mediaURL(for: existing)
        var replacementBytes = try Data(contentsOf: source)
        replacementBytes[0] ^= 1
        try replacementBytes.write(to: existingURL)

        // Simulate the source temporarily pointing to different, same-size bytes during copy.
        let importer = VideoImporter(container: container, fileManager: SubstitutingCopy(source: existingURL))
        do {
            _ = try await importer.importVideo(from: source, existingContents: [existing])
            XCTFail("The managed copy is a duplicate")
        } catch {
            XCTAssertEqual(error as? HikariError, .duplicateContent)
        }
        XCTAssertEqual(try files.contentsOfDirectory(atPath: container.mediaDirectoryURL.path), ["existing.mov"])
    }
}

private final class SubstitutingCopy: FileManager, @unchecked Sendable {
    let source: URL

    init(source: URL) {
        self.source = source
        super.init()
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try super.copyItem(at: source, to: dstURL)
    }
}

private final class FailingMove: FileManager, @unchecked Sendable {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteOutOfSpace)
    }
}
