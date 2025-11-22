import SwiftUI
import AppKit
import CoreImage

actor ImageProcessor {
    static let shared = ImageProcessor()
    
    func extractDominantColor(from image: NSImage) -> Color? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        // Resize image for faster processing
        let width = min(100, cgImage.width)
        let height = min(100, cgImage.height)
        
        guard let resizedCGImage = resizeCGImage(cgImage, width: width, height: height) else {
            return nil
        }
        
        // Extract pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(resizedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Calculate average color
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var count: CGFloat = 0
        
        for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
            let red = CGFloat(pixelData[i]) / 255.0
            let green = CGFloat(pixelData[i + 1]) / 255.0
            let blue = CGFloat(pixelData[i + 2]) / 255.0
            
            // Skip very dark or very light pixels
            let brightness = (red + green + blue) / 3.0
            if brightness > 0.1 && brightness < 0.9 {
                r += red
                g += green
                b += blue
                count += 1
            }
        }
        
        guard count > 0 else { return nil }
        
        r /= count
        g /= count
        b /= count
        
        // Enhance saturation slightly
        let saturationBoost: CGFloat = 1.2
        let maxComponent = max(r, g, b)
        if maxComponent > 0 {
            r = min(1.0, r * saturationBoost)
            g = min(1.0, g * saturationBoost)
            b = min(1.0, b * saturationBoost)
        }
        
        return Color(red: Double(r), green: Double(g), blue: Double(b))
    }
    
    private func resizeCGImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        
        context?.interpolationQuality = .low
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return context?.makeImage()
    }
    
    func blurImage(_ image: NSImage, radius: Double) -> NSImage? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let ciImage = CIImage(bitmapImageRep: bitmap) else {
            return nil
        }
        
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        
        guard let outputImage = filter?.outputImage else { return nil }
        
        let context = CIContext()
        // Crop to original extent to avoid growing the image
        let cgImage = context.createCGImage(outputImage, from: ciImage.extent)
        
        guard let finalCGImage = cgImage else { return nil }
        return NSImage(cgImage: finalCGImage, size: image.size)
    }
}
