import AppKit
import Foundation
import SwiftUI

enum ScreenshotCaptureError: Error, LocalizedError {
    case noProjection
    case renderFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .noProjection: "the fixture did not publish a projection"
        case .renderFailed: "the off-screen view hierarchy produced no bitmap"
        case .pngEncodingFailed: "AppKit could not encode the rendered bitmap as PNG"
        }
    }
}





@MainActor
enum ScreenshotCapture {
    static let scale: CGFloat = 2
    static let defaultSize = CGSize(width: 1000, height: 700)

    struct Result: Equatable, Sendable {
        let pixelsWide: Int
        let pixelsHigh: Int
        let bytes: Int
    }

    static func logicalSize(for options: LaunchOptions) -> CGSize {
        guard let frame = options.frame,
              frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0 else {
            return defaultSize
        }
        return frame.size
    }

    static func write(store: CoreStore, options: LaunchOptions, to output: URL) throws -> Result {
        guard store.projection != nil else { throw ScreenshotCaptureError.noProjection }
        let size = logicalSize(for: options)
        let appearance = options.setAppearanceOnLaunch ?? store.projection?.view.settings.appearance ?? .system
        let colorScheme: ColorScheme = appearance == .dark ? .dark : .light
        let content = SettingsShell(store: store, options: options, submit: { _ in })
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, colorScheme)
            .environment(\.displayScale, scale)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }

        let bounds = CGRect(origin: .zero, size: size)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = bounds
        let window = NSWindow(
            contentRect: bounds,
            styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        defer {
            window.contentView = nil
            window.close()
        }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let pixelsWide = Int((size.width * scale).rounded())
        let pixelsHigh = Int((size.height * scale).rounded())
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelsWide * 4,
            bitsPerPixel: 32
        ) else { throw ScreenshotCaptureError.renderFailed }
        bitmap.size = size
        hosting.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotCaptureError.pngEncodingFailed
        }

        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: output, options: .atomic)
        return Result(pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bytes: png.count)
    }
}
