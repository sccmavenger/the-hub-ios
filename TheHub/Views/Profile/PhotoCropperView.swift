import SwiftUI
import ImageIO

/// Wraps a picked image so it can drive an item-based sheet.
struct CropCandidate: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Pinch-to-zoom, drag-to-position circular cropper for the profile photo.
/// Delivers the framed square as JPEG data sized for upload.
struct PhotoCropperView: View {
    let image: UIImage
    let onCrop: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let outputSide: CGFloat = 1200
    private let maxZoom: CGFloat = 6

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let side = max(min(geo.size.width, geo.size.height) - 32, 100)
                VStack(spacing: 16) {
                    Spacer()
                    cropCanvas(side: side)
                    Text("Pinch to zoom · Drag to position")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.hubBackground.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let data = croppedJPEG(side: side) {
                                onCrop(data)
                            }
                            dismiss()
                        }
                        .bold()
                    }
                }
            }
            .navigationTitle("Position Your Photo")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private func cropCanvas(side: CGFloat) -> some View {
        let display = displaySize(side: side, zoom: zoom)
        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: display.width, height: display.height)
                .offset(offset)
        }
        .frame(width: side, height: side)
        .clipped()
        .overlay(dimmingOverlay)
        .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(dragGesture(side: side).simultaneously(with: zoomGesture(side: side)))
    }

    /// Darkens everything outside the circle so the athlete sees the true avatar framing.
    private var dimmingOverlay: some View {
        Rectangle()
            .fill(Color.black.opacity(0.55))
            .mask {
                Rectangle()
                    .overlay(Circle().blendMode(.destinationOut))
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }

    // MARK: - Geometry

    private func displaySize(side: CGFloat, zoom: CGFloat) -> CGSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return .zero }
        let fill = side / min(size.width, size.height)
        return CGSize(width: size.width * fill * zoom, height: size.height * fill * zoom)
    }

    private func clampedOffset(_ proposed: CGSize, side: CGFloat, zoom: CGFloat) -> CGSize {
        let display = displaySize(side: side, zoom: zoom)
        let maxX = max(0, (display.width - side) / 2)
        let maxY = max(0, (display.height - side) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func dragGesture(side: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, side: side, zoom: zoom)
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func zoomGesture(side: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(committedZoom * value.magnification, 1), maxZoom)
                offset = clampedOffset(offset, side: side, zoom: zoom)
            }
            .onEnded { _ in
                committedZoom = zoom
                committedOffset = offset
            }
    }

    // MARK: - Output

    /// Re-renders exactly what's visible in the square at upload resolution.
    private func croppedJPEG(side: CGFloat) -> Data? {
        let display = displaySize(side: side, zoom: zoom)
        guard display != .zero else { return nil }
        let scale = outputSide / side
        let origin = CGPoint(
            x: (side - display.width) / 2 + offset.width,
            y: (side - display.height) / 2 + offset.height
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(
            size: CGSize(width: outputSide, height: outputSide),
            format: format
        ).image { _ in
            image.draw(in: CGRect(
                x: origin.x * scale,
                y: origin.y * scale,
                width: display.width * scale,
                height: display.height * scale
            ))
        }
        return rendered.jpegData(compressionQuality: 0.85)
    }

    /// Memory-bounded decode of picked photo data — a 48 MP camera image
    /// never gets fully decoded into RAM.
    static func downsampledImage(data: Data, maxDimension: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    let sample = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 900)).image { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        UIColor.systemOrange.setFill()
        context.fill(CGRect(x: 700, y: 250, width: 200, height: 400))
    }
    return PhotoCropperView(image: sample) { _ in }
}
