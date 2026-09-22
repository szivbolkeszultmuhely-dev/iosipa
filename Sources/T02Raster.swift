import UIKit
import Foundation
import CoreGraphics

/// Single, intentionally short test pattern. This DOES NOT generate a fiscal receipt.
enum T02Raster {
    static let width = 384
    private static let bytesPerRow = width / 8

    static func makeTestJob() throws -> Data {
        let size = CGSize(width: width, height: 352)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: fmt).image { renderer in
            let ctx = renderer.cgContext
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let center = NSMutableParagraphStyle()
            center.alignment = .center
            let heading: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 30),
                .foregroundColor: UIColor.black, .paragraphStyle: center
            ]
            let text: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22),
                .foregroundColor: UIColor.black, .paragraphStyle: center
            ]
            ("MOMENTS POS" as NSString).draw(in: CGRect(x: 8, y: 26, width: 368, height: 46), withAttributes: heading)
            ("AIMO T02 TESZT" as NSString).draw(in: CGRect(x: 8, y: 92, width: 368, height: 40), withAttributes: text)
            ("NEM ÉRVÉNYES NYUGTA" as NSString).draw(in: CGRect(x: 8, y: 147, width: 368, height: 70), withAttributes: text)
            (DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short) as NSString)
                .draw(in: CGRect(x: 8, y: 226, width: 368, height: 40), withAttributes: text)
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(CGRect(x: 20, y: 289, width: 344, height: 3))
            ctx.fill(CGRect(x: 20, y: 306, width: 344, height: 3))
        }
        guard let bitmap = image.cgImage else { throw RasterError.conversionFailed }
        return try encode(bitmap)
    }

    enum RasterError: Error { case conversionFailed }

    private static func encode(_ image: CGImage) throws -> Data {
        let height = image.height
        guard image.width == width, height > 0, height <= 800 else { throw RasterError.conversionFailed }
        var gray = [UInt8](repeating: 255, count: width * height)
        let drawn = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width,
                                          height: height, bitsPerComponent: 8,
                                          bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw RasterError.conversionFailed }

        // Protocol: ESC @, then GS v 0 raster strips of at most 128 rows, feed.
        var output = Data([0x1B, 0x40])
        for start in stride(from: 0, to: height, by: 128) {
            let rows = min(128, height - start)
            output.append(contentsOf: [0x1D, 0x76, 0x30, 0x00,
                                       UInt8(bytesPerRow), 0x00,
                                       UInt8(rows & 255), UInt8(rows >> 8)])
            // Hardware calibration: this renderer's row order is vertically inverted
            // for the T02, but the printer expects normal left-to-right raster bytes.
            // Therefore ONLY reverse row order; do not mirror pixels and do not
            // reverse bit order inside each byte.
            for row in start..<(start + rows) {
                let sourceRow = height - 1 - row
                let offset = sourceRow * width
                for n in 0..<bytesPerRow {
                    var packed: UInt8 = 0
                    for bit in 0..<8 {
                        if gray[offset + n * 8 + bit] < 160 {
                            packed |= UInt8(0x80 >> bit)
                        }
                    }
                    output.append(packed)
                }
            }
        }
        output.append(contentsOf: [0x1B, 0x64, 0x03])
        return output
    }
}
