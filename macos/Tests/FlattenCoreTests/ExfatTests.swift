import XCTest
@testable import FlattenCore

/// Essai réel sur un disque exFAT, lancé seulement si EXFAT_TEST_DIR pointe vers un dossier d'un tel disque
/// (par exemple une image créée par `hdiutil create -size 50m -fs ExFAT`). Ailleurs, le test est ignoré.
final class ExfatTests: XCTestCase {
    func testCopyToExfatLeavesNoAppleDoubleFile() throws {
        guard let dir = ProcessInfo.processInfo.environment["EXFAT_TEST_DIR"] else { throw XCTSkip("EXFAT_TEST_DIR absent") }
        XCTAssertFalse(hasNativeAttributes(dir))
        let src = NSTemporaryDirectory() + "flat-exfat-src.dll"
        try Data("x".utf8).write(to: URL(fileURLWithPath: src))
        _ = setxattr(src, "com.apple.test", "1", 1, 0, 0)
        let dst = dir + "/Plugins/EngineFixes.dll"
        XCTAssertEqual(try optimizedCopyFile(src, dst, useHardlinks: true), "copy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/Plugins/._EngineFixes.dll"))
    }

    func testNativeVolumeKeepsAttributes() {
        XCTAssertTrue(hasNativeAttributes(NSTemporaryDirectory()))
    }
}
