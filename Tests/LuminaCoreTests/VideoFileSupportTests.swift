import Foundation
import XCTest
@testable import LuminaCore

final class VideoFileSupportTests: XCTestCase {
    func testRecognizesCommonMovieContainers() {
        for filename in ["wallpaper.mp4", "wallpaper.mov", "wallpaper.m4v"] {
            XCTAssertEqual(
                VideoFileSupport.storageFileExtension(
                    for: URL(fileURLWithPath: "/tmp/\(filename)")
                ),
                URL(fileURLWithPath: filename).pathExtension
            )
        }
    }

    func testNormalizesUppercaseMovieExtension() {
        XCTAssertEqual(
            VideoFileSupport.storageFileExtension(
                for: URL(fileURLWithPath: "/tmp/WALLPAPER.MOV")
            ),
            "mov"
        )
    }

    func testRejectsNonMovieFiles() {
        XCTAssertNil(
            VideoFileSupport.storageFileExtension(
                for: URL(fileURLWithPath: "/tmp/wallpaper.txt")
            )
        )
    }
}
