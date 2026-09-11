import AppKit
import CodexMultiResources
import Foundation

enum TrayIcon {
    static func image(bundle: Bundle? = nil) -> NSImage? {
        if let bundle {
            return image(in: bundle)
        }
        return image(in: .main) ?? image(in: CodexMultiResourceBundle.bundle)
    }

    private static func image(in bundle: Bundle) -> NSImage? {
        guard let source = bundle.image(forResource: "TrayIcon"),
              let image = source.copy() as? NSImage else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    static func resourceURL(named fileName: String, bundle: Bundle? = nil) -> URL? {
        let file = fileName as NSString
        if let bundle {
            return bundle.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension)
        }
        return Bundle.main.url(
            forResource: file.deletingPathExtension,
            withExtension: file.pathExtension
        ) ?? CodexMultiResourceBundle.bundle.url(
            forResource: file.deletingPathExtension,
            withExtension: file.pathExtension
        )
    }
}
