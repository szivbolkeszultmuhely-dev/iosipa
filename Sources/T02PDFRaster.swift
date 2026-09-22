import Foundation
import UIKit
import PDFKit
import CoreGraphics

/// Renders the PDF obtained from the authenticated POS archive. It does not
/// reconstruct a receipt from transaction data or mutate the source PDF.
///
/// NOTE: The T02's byte packing below is intentionally the EXACT packing that
/// was hardware-validated in T02Raster.swift 1.0.4: reverse rows ONLY, never
/// reverse columns or bits. Do not change it without a physical printer test.
enum T02PDFRaster {
    enum RasterError: LocalizedError {
        case invalidPDF
        case unsupportedRotation
        case invalidPage
        case tooLong
        case imageConversion

        var errorDescription: String? {
            switch self {
            case .invalidPDF: return "A kapott fájl nem olvasható PDF."
            case .unsupportedRotation: return "A PDF elforgatott oldalt tartalmaz; a pontos nyomtatáshoz ellenőrzés szükséges."
            case .invalidPage: return "A PDF egyik oldalának mérete nem megfelelő."
            case .tooLong: return "A PDF túl hosszú a biztonságos T02 nyomtatáshoz. Nem vágunk le belőle adatot."
            case .imageConversion: return "A PDF képpé alakítása sikertelen; semmit nem küldtünk a nyomtatóra."
            }
        }
    }

    private static let width = 384
    private static let bytesPerRow = width / 8
    private static let maxPageHeight = 12_000
    private static let maxTotalHeight = 18_000
    private static let maxPages = 4

    static func makeJob(fromPDF data: Data) throws -> Data {
        guard let document = PDFDocument(data: data),
              (1...maxPages).contains(document.pageCount) else { throw RasterError.invalidPDF }

        // Preserve every page. Reject oversized PDFs rather than silently
        // truncating the bottom of a receipt or dropping subsequent pages.
        var pageSpecs: [(page: PDFPage, bounds: CGRect, height: Int)] = []
        var totalRows = 0
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { throw RasterError.invalidPDF }
            guard page.rotation % 360 == 0 else { throw RasterError.unsupportedRotation }
            let bounds = page.bounds(for: .cropBox)
            guard bounds.width.isFinite, bounds.height.isFinite,
                  bounds.width > 0, bounds.height > 0 else { throw RasterError.invalidPage }
            let estimated = bounds.height * CGFloat(width) / bounds.width
            guard estimated.isFinite, estimated > 0,
                  estimated <= CGFloat(maxPageHeight) else { throw RasterError.tooLong }
            let height = Int(estimated.rounded(.up))
            totalRows += height
            guard totalRows <= maxTotalHeight else { throw RasterError.tooLong }
            pageSpecs.append((page, bounds, height))
        }

        var output = Data([0x1B, 0x40]) // ESC @, same as 1.0.4
        for spec in pageSpecs {
            let scaledSize = CGSize(width: CGFloat(width), height: CGFloat(spec.height))
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: scaledSize, format: format).image { renderer in
                let context = renderer.cgContext
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(origin: .zero, size: scaledSize))
                context.saveGState()
                let scale = CGFloat(width) / spec.bounds.width
                // UIKit images start top-left; PDF coordinates start bottom-left.
                // The result is upright in the UIImage/CGImage before passing
                // through the already validated 1.0.4 raster byte order.
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -spec.bounds.minX, y: spec.bounds.maxY)
                context.scaleBy(x: 1, y: -1)
                spec.page.draw(with: .cropBox, to: context)
                context.restoreGState()
            }
            guard let bitmap = image.cgImage,
                  bitmap.width == width, bitmap.height == spec.height else {
                throw RasterError.imageConversion
            }
            try appendRaster(bitmap, to: &output)
            output.append(contentsOf: [0x1B, 0x64, 0x03]) // feed after EACH page
        }
        guard output.count < 1_000_000 else { throw RasterError.tooLong }
        return output
    }

    private static func appendRaster(_ image: CGImage, to output: inout Data) throws {
        let height = image.height
        var gray = [UInt8](repeating: 255, count: width * height)
        let rendered = gray.withUnsafeMutableBytes { buffer -> Bool in
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
        guard rendered else { throw RasterError.imageConversion }

        for start in stride(from: 0, to: height, by: 128) {
            let rows = min(128, height - start)
            output.append(contentsOf: [0x1D, 0x76, 0x30, 0x00,
                                       UInt8(bytesPerRow), 0x00,
                                       UInt8(rows & 255), UInt8(rows >> 8)])
            // 1.0.4 verified byte order: only reverse scanline order.
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
    }
}
