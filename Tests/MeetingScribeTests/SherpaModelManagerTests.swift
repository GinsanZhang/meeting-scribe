import Foundation
import XCTest
@testable import MeetingScribe

final class SherpaModelManagerTests: XCTestCase {
    func testCompleteModelFilesAreRecognized() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try createSparseFile(at: root.appendingPathComponent("encoder.int8.onnx"), size: 158_000_000)
        try createSparseFile(at: root.appendingPathComponent("decoder.int8.onnx"), size: 68_000_000)
        try createSparseFile(at: root.appendingPathComponent("tokens.txt"), size: 76_000)

        XCTAssertTrue(SherpaModelManager.isDownloaded(in: root, fileManager: .default))
    }

    func testPartialModelFilesAreNotRecognizedAsDownloaded() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data().write(to: root.appendingPathComponent("encoder.int8.onnx"))
        try Data(repeating: 1, count: 1024).write(to: root.appendingPathComponent("decoder.int8.onnx"))
        try Data(repeating: 1, count: 128).write(to: root.appendingPathComponent("tokens.txt"))

        XCTAssertFalse(SherpaModelManager.isDownloaded(in: root, fileManager: .default))
    }

    private func createSparseFile(at url: URL, size: Int64) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
    }
}
