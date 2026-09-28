import Foundation
import UIKit
import CoreGraphics

/// 40 × 15 mm Code 128-B product label for the AIMO T02.
///
/// The barcode encoding mirrors the existing WordPress label workspace:
/// printable ASCII only, max. 13 characters for the physical 40 mm label.
/// The T02 raster byte order is the hardware-validated 1.0.4 order:
/// reverse scanline order only; never mirror columns or bits.
enum T02BarcodeLabelRaster {
    enum LabelError: LocalizedError {
        case emptyCode
        case unsupportedCharacters
        case tooLong
        case invalidQuantity
        case imageConversion

        var errorDescription: String? {
            switch self {
            case .emptyCode:
                return "Ehhez a termékhez nincs nyomtatható vonalkód."
            case .unsupportedCharacters:
                return "A Code 128 címke csak ékezet nélküli ASCII karaktereket támogat."
            case .tooLong:
                return "A vonalkód túl hosszú a 40 × 15 mm-es címkéhez (legfeljebb 13 ASCII karakter)."
            case .invalidQuantity:
                return "Egyszerre 1–100 címke nyomtatható."
            case .imageConversion:
                return "A vonalkódcímke képpé alakítása sikertelen."
            }
        }
    }

    private static let printerWidth = 384
    private static let bytesPerRow = printerWidth / 8

    // 203 dpi: 40 mm ≈ 320 px, 15 mm ≈ 120 px.
    private static let labelHeight = 120
    private static let contentWidth: CGFloat = 304 // 38 mm
    private static let barcodeTop: CGFloat = 7
    private static let barcodeBottom: CGFloat = 88

    // Code 128 symbol-width patterns, identical to assets/js/labels.js.
    private static let patterns = [
        "212222","222122","222221","121223","121322","131222","122213","122312","132212","221213",
        "221312","231212","112232","122132","122231","113222","123122","123221","223211","221132",
        "221231","213212","223112","312131","311222","321122","321221","312212","322112","322211",
        "212123","212321","232121","111323","131123","131321","112313","132113","132311","211313",
        "231113","231311","112133","112331","132131","113123","113321","133121","313121","211331",
        "231131","213113","213311","213131","311123","311321","331121","312113","312311","332111",
        "314111","221411","431111","111224","111422","121124","121421","141122","141221","112214",
        "112412","122114","122411","142112","142211","241211","221114","413111","241112","134111",
        "111242","121142","121241","114212","124112","124211","411212","421112","421211","212141",
        "214121","412121","111143","111341","131141","114113","114311","411113","411311","113141",
        "114131","311141","411131","211412","211214","211232","2331112"
    ]

    private struct Encoded {
        let text: String
        let patterns: [String]
        let modules: Int
    }

    static func makeJob(code rawCode: String, quantity: Int) throws -> Data {
        guard (1...100).contains(quantity) else { throw LabelError.invalidQuantity }
        let encoded = try encode(rawCode)
        let image = try render(encoded)

        var raster = Data()
        try appendRaster(image, to: &raster)

        // Reset once, print N exact 15 mm rasters, then advance enough paper for easy tearing.
        var output = Data([0x1B, 0x40])
        for _ in 0..<quantity {
            output.append(raster)
        }
        output.append(contentsOf: [0x1B, 0x64, 0x03])
        return output
    }

    private static func encode(_ rawCode: String) throws -> Encoded {
        let text = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LabelError.emptyCode }

        let scalars = Array(text.unicodeScalars)
        guard scalars.allSatisfy({ (32...126).contains(Int($0.value)) }) else {
            throw LabelError.unsupportedCharacters
        }

        let dataCodes = scalars.map { Int($0.value) - 32 }
        var checksum = 104 // Code Set B start.
        for (index, code) in dataCodes.enumerated() {
            checksum += code * (index + 1)
        }

        let codes = [104] + dataCodes + [checksum % 103, 106]
        let encodedPatterns = codes.map { patterns[$0] }
        let modules = encodedPatterns.reduce(0) { total, pattern in
            total + pattern.compactMap { Int(String($0)) }.reduce(0, +)
        }

        // Keep exactly the same physical guard as the WordPress label tool.
        let moduleWidthMM = 38.0 / Double(modules + 20)
        guard moduleWidthMM >= 0.19, scalars.count <= 13 else { throw LabelError.tooLong }

        return Encoded(text: text, patterns: encodedPatterns, modules: modules)
    }

    private static func render(_ encoded: Encoded) throws -> CGImage {
        let size = CGSize(width: printerWidth, height: labelHeight)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            context.setAllowsAntialiasing(false)
            context.setShouldAntialias(false)
            context.interpolationQuality = .none
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(UIColor.black.cgColor)

            let contentOrigin = (CGFloat(printerWidth) - contentWidth) / 2.0
            let quietModules: CGFloat = 10
            let moduleWidth = contentWidth / CGFloat(encoded.modules + 20)

            var offset = 0
            for pattern in encoded.patterns {
                var isBar = true
                for character in pattern {
                    guard let elementWidth = Int(String(character)) else { continue }
                    if isBar {
                        let left = (contentOrigin + (quietModules + CGFloat(offset)) * moduleWidth).rounded()
                        let right = (contentOrigin + (quietModules + CGFloat(offset + elementWidth)) * moduleWidth).rounded()
                        let width = max(1, right - left)
                        context.fill(CGRect(x: left, y: barcodeTop,
                                          width: width, height: barcodeBottom - barcodeTop))
                    }
                    offset += elementWidth
                    isBar.toggle()
                }
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]
            (encoded.text as NSString).draw(
                in: CGRect(x: 32, y: 95, width: 320, height: 18),
                withAttributes: attributes
            )
        }

        guard let bitmap = image.cgImage,
              bitmap.width == printerWidth,
              bitmap.height == labelHeight else {
            throw LabelError.imageConversion
        }
        return bitmap
    }

    private static func appendRaster(_ image: CGImage, to output: inout Data) throws {
        let height = image.height
        var gray = [UInt8](repeating: 255, count: printerWidth * height)
        let rendered = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: printerWidth,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: printerWidth,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }

            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: printerWidth, height: height))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: printerWidth, height: height))
            return true
        }
        guard rendered else { throw LabelError.imageConversion }

        for start in stride(from: 0, to: height, by: 128) {
            let rows = min(128, height - start)
            output.append(contentsOf: [
                0x1D, 0x76, 0x30, 0x00,
                UInt8(bytesPerRow), 0x00,
                UInt8(rows & 255), UInt8(rows >> 8)
            ])
            for row in start..<(start + rows) {
                let sourceRow = height - 1 - row
                let offset = sourceRow * printerWidth
                for byteIndex in 0..<bytesPerRow {
                    var packed: UInt8 = 0
                    for bit in 0..<8 {
                        if gray[offset + byteIndex * 8 + bit] < 160 {
                            packed |= UInt8(0x80 >> bit)
                        }
                    }
                    output.append(packed)
                }
            }
        }
    }
}
