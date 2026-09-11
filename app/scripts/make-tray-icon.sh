#!/usr/bin/swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvasPoints: CGFloat = 18
let supersampling = 4
let center = CGPoint(x: 9, y: 9)
let orbitRadius: CGFloat = 5.2
let tileSide: CGFloat = 6.4
let tileRadius: CGFloat = 1.6
let outlineWidth: CGFloat = 1.5
let centerDotDiameter: CGFloat = 2.2
let outputDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Resources", isDirectory: true)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func tileCenter(angleDegrees: CGFloat) -> CGPoint {
    let radians = angleDegrees * .pi / 180
    return CGPoint(
        x: center.x + orbitRadius * cos(radians),
        y: center.y + orbitRadius * sin(radians)
    )
}

func tileBounds(center: CGPoint) -> CGRect {
    CGRect(
        x: center.x - tileSide / 2,
        y: center.y - tileSide / 2,
        width: tileSide,
        height: tileSide
    )
}

func render(scale: Int) -> CGImage {
    let outputPixels = Int(canvasPoints) * scale
    let renderPixels = outputPixels * supersampling
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: renderPixels,
        height: renderPixels,
        bitsPerComponent: 8,
        bytesPerRow: renderPixels * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("could not create the supersampled bitmap context")
    }

    let pointScale = CGFloat(scale * supersampling)
    context.scaleBy(x: pointScale, y: pointScale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.setFillColor(gray: 0, alpha: 1)
    context.setStrokeColor(gray: 0, alpha: 1)

    let filledTile = tileBounds(center: tileCenter(angleDegrees: 90))
    context.addPath(CGPath(
        roundedRect: filledTile,
        cornerWidth: tileRadius,
        cornerHeight: tileRadius,
        transform: nil
    ))
    context.fillPath()

    context.setLineWidth(outlineWidth)
    for angle in [CGFloat(210), CGFloat(330)] {
        let strokeInset = outlineWidth / 2
        let outlinedTile = tileBounds(center: tileCenter(angleDegrees: angle))
            .insetBy(dx: strokeInset, dy: strokeInset)
        context.addPath(CGPath(
            roundedRect: outlinedTile,
            cornerWidth: tileRadius - strokeInset,
            cornerHeight: tileRadius - strokeInset,
            transform: nil
        ))
        context.strokePath()
    }

    let dotBounds = CGRect(
        x: center.x - centerDotDiameter / 2,
        y: center.y - centerDotDiameter / 2,
        width: centerDotDiameter,
        height: centerDotDiameter
    )
    context.fillEllipse(in: dotBounds)

    guard let supersampled = context.makeImage(),
          let outputContext = CGContext(
              data: nil,
              width: outputPixels,
              height: outputPixels,
              bitsPerComponent: 8,
              bytesPerRow: outputPixels * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        fail("could not create the output bitmap context")
    }
    outputContext.interpolationQuality = .high
    outputContext.draw(
        supersampled,
        in: CGRect(x: 0, y: 0, width: outputPixels, height: outputPixels)
    )
    guard let image = outputContext.makeImage() else {
        fail("could not create the output image")
    }
    return image
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fail("could not create the PNG destination at \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fail("could not write \(url.path)")
    }
}

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

for scale in 1...3 {
    let suffix = scale == 1 ? "" : "@\(scale)x"
    let url = outputDirectory.appendingPathComponent("TrayIcon\(suffix).png")
    let image = render(scale: scale)
    write(image, to: url)
    let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    print("Generated \(url.path): \(image.width)x\(image.height), \(bytes) bytes")
}
