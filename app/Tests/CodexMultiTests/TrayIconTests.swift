import AppKit
import ImageIO
import XCTest
@testable import CodexMulti

final class TrayIconTests: XCTestCase {
    func testTrayIconLoadsAsAnEighteenPointTemplateImage() throws {
        let image = try XCTUnwrap(TrayIcon.image())

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    }

    func testTrayIconPixelsAreBlackOrTransparentAtEveryScale() throws {
        let expectedSizes = ["TrayIcon.png": 18, "TrayIcon@2x.png": 36, "TrayIcon@3x.png": 54]
        for (name, size) in expectedSizes {
            let url = try XCTUnwrap(TrayIcon.resourceURL(named: name))
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue
            let context = try XCTUnwrap(CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let bytes = try XCTUnwrap(context.data).bindMemory(
                to: UInt8.self,
                capacity: image.height * context.bytesPerRow
            )

            XCTAssertEqual(image.width, size, name)
            XCTAssertEqual(image.height, size, name)

            for y in 0..<image.height {
                for x in 0..<image.width {
                    let offset = y * context.bytesPerRow + x * 4
                    let red = bytes[offset]
                    let green = bytes[offset + 1]
                    let blue = bytes[offset + 2]
                    let alpha = bytes[offset + 3]
                    XCTAssertTrue(alpha == 0 || (red == 0 && green == 0 && blue == 0), "\(name) contains a color pixel at \(x),\(y)")
                }
            }
        }
    }
}
