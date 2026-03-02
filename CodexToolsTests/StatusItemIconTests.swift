@testable import CodexTools
import AppKit
import XCTest

final class StatusItemIconTests: XCTestCase {
    func testStatusItemIconIsTemplateWithExpectedCanvasSize() {
        let image = makeStatusItemImage()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size.width, 18)
        XCTAssertEqual(image.size.height, 18)
        XCTAssertTrue(imageHasVisiblePixels(image))
    }

    private func imageHasVisiblePixels(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return false
        }

        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y) else {
                    continue
                }
                if color.alphaComponent > 0.01 {
                    return true
                }
            }
        }

        return false
    }
}
