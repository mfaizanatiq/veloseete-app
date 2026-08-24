import MapKit
import SwiftUI
import UIKit

/// Classy trip share — full-bleed map, one giant lime number, almost nothing else.
enum TripShareComposer {
    /// 9:16 story frame
    static let canvasSize = CGSize(width: 1080, height: 1920)

    private static let lime = UIColor(red: 0xD9 / 255, green: 0xFC / 255, blue: 0x55 / 255, alpha: 1)
    private static let void = UIColor(red: 0x05 / 255, green: 0x06 / 255, blue: 0x05 / 255, alpha: 1)
    private static let cardRadius: CGFloat = 56
    private static let margin: CGFloat = 28

    static func render(
        trip: Trip,
        unit: String,
        vehicleName: String,
        trackyMood: TrackyMood = .chill
    ) async -> UIImage? {
        let card = CGRect(
            x: margin,
            y: margin,
            width: canvasSize.width - margin * 2,
            height: canvasSize.height - margin * 2
        )
        let coords = displayCoordinates(for: trip)
        // MapKit rejects huge snapshots (~3k×5k). Match card points @2x — reliable and sharp.
        let mapImage = await snapshotMap(coordinates: coords, size: card.size, trackyMood: trackyMood)
            ?? placeholderMap(size: card.size)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { ctx in
            let cg = ctx.cgContext
            void.setFill()
            cg.fill(CGRect(origin: .zero, size: canvasSize))

            // Clipped full-bleed map card
            cg.saveGState()
            let cardPath = UIBezierPath(roundedRect: card, cornerRadius: cardRadius)
            cardPath.addClip()
            drawAspectFill(mapImage, in: card)

            // Soft bottom wash so type reads — keep map visible
            let washHeight = card.height * 0.38
            let wash = CGRect(x: card.minX, y: card.maxY - washHeight, width: card.width, height: washHeight)
            let washColors = [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.42).cgColor,
                UIColor.black.withAlphaComponent(0.68).cgColor
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: washColors,
                locations: [0, 0.55, 1]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: wash.midX, y: wash.minY),
                    end: CGPoint(x: wash.midX, y: wash.maxY),
                    options: []
                )
            }

            // Soft center vignette behind the hero number
            let vignetteCenter = CGPoint(x: card.midX, y: card.midY - card.height * 0.06)
            let vignetteColors = [
                UIColor.black.withAlphaComponent(0.32).cgColor,
                UIColor.clear.cgColor
            ] as CFArray
            if let radial = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: vignetteColors,
                locations: [0, 1]
            ) {
                cg.drawRadialGradient(
                    radial,
                    startCenter: vignetteCenter,
                    startRadius: 0,
                    endCenter: vignetteCenter,
                    endRadius: card.width * 0.42,
                    options: []
                )
            }

            // Hero metric — lime, centered, owns the frame
            let distance = distanceParts(trip.distanceKm, unit: unit)
            let heroFont = boldFont(size: heroPointSize(for: distance.value))
            let heroAttrs: [NSAttributedString.Key: Any] = [
                .font: heroFont,
                .foregroundColor: lime
            ]
            let heroSize = (distance.value as NSString).size(withAttributes: heroAttrs)
            let heroOrigin = CGPoint(
                x: card.midX - heroSize.width / 2,
                y: vignetteCenter.y - heroSize.height / 2
            )
            (distance.value as NSString).draw(at: heroOrigin, withAttributes: heroAttrs)

            // Tiny unit under the number
            let unitFont = mediumFont(size: 36)
            let unitAttrs: [NSAttributedString.Key: Any] = [
                .font: unitFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.72),
                .kern: 4
            ]
            let unitSize = (distance.unit.uppercased() as NSString).size(withAttributes: unitAttrs)
            (distance.unit.uppercased() as NSString).draw(
                at: CGPoint(x: card.midX - unitSize.width / 2, y: heroOrigin.y + heroSize.height - 18),
                withAttributes: unitAttrs
            )

            // Bottom-left caption — one quiet line
            let inset: CGFloat = 48
            let caption = shareCaption(trip: trip, vehicleName: vehicleName)
            let captionFont = mediumFont(size: 34)
            let captionAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: UIColor.white
            ]
            let captionY = card.maxY - inset - 78
            (caption as NSString).draw(
                at: CGPoint(x: card.minX + inset, y: captionY),
                withAttributes: captionAttrs
            )

            // Slim lime bar — classy accent, not a stats strip
            let barWidth = card.width - inset * 2
            let barHeight: CGFloat = 10
            let barY = card.maxY - inset - 28
            let track = CGRect(x: card.minX + inset, y: barY, width: barWidth, height: barHeight)
            UIColor.white.withAlphaComponent(0.18).setFill()
            UIBezierPath(roundedRect: track, cornerRadius: barHeight / 2).fill()

            let fillFraction = min(max(CGFloat(trip.durationSec / 3600.0), 0.12), 1.0)
            let fill = CGRect(x: track.minX, y: track.minY, width: track.width * fillFraction, height: barHeight)
            lime.setFill()
            UIBezierPath(roundedRect: fill, cornerRadius: barHeight / 2).fill()

            // Whisper brand — top trailing, not a footer block
            let brand = "VELOSEETE"
            let brandFont = boldFont(size: 22)
            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: brandFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.55),
                .kern: 3
            ]
            let brandSize = (brand as NSString).size(withAttributes: brandAttrs)
            (brand as NSString).draw(
                at: CGPoint(x: card.maxX - inset - brandSize.width, y: card.minY + inset + 8),
                withAttributes: brandAttrs
            )

            cg.restoreGState()
        }
    }

    // MARK: - Map

    private static func displayCoordinates(for trip: Trip) -> [CLLocationCoordinate2D] {
        let points: [TripCoordinate]
        if trip.route.count >= 2 {
            points = TripTrackingLogic.mapDisplayRoute(id: trip.id, points: trip.route, maximumPoints: 600)
        } else {
            points = [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
        }
        return points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private static func snapshotMap(
        coordinates: [CLLocationCoordinate2D],
        size: CGSize,
        trackyMood: TrackyMood
    ) async -> UIImage? {
        // Prefer a slightly shorter frame for MapKit reliability, then aspect-fill the card.
        let snapSize = CGSize(
            width: min(max(size.width, 640), 1200),
            height: min(max(size.height * 0.72, 900), 1600)
        )

        let options = MKMapSnapshotter.Options()
        options.size = snapSize
        options.scale = 2
        options.mapType = .standard
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .dark),
            UITraitCollection(displayScale: 2)
        ])

        if coordinates.count >= 2 {
            // Bias the frame so the route sits slightly low — leaves room for the hero number.
            // Extra pad so start pin + Tracky aren’t clipped at the edge.
            var fitted = region(for: coordinates)
            fitted.center.latitude += fitted.span.latitudeDelta * 0.08
            fitted.span.latitudeDelta *= 1.35
            fitted.span.longitudeDelta *= 1.35
            options.region = fitted
        } else if let only = coordinates.first {
            options.region = MKCoordinateRegion(center: only, latitudinalMeters: 3_200, longitudinalMeters: 3_200)
        } else {
            options.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 25.2854, longitude: 51.5310),
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            )
        }

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            return drawRoute(on: snapshot, coordinates: coordinates, trackyMood: trackyMood)
        } catch {
            print("[TripShare] snapshot failed (\(Int(snapSize.width))×\(Int(snapSize.height))@2x): \(error)")
            // One smaller retry — some devices reject taller frames.
            return await snapshotMapFallback(coordinates: coordinates, trackyMood: trackyMood)
        }
    }

    private static func snapshotMapFallback(
        coordinates: [CLLocationCoordinate2D],
        trackyMood: TrackyMood
    ) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.size = CGSize(width: 1080, height: 1080)
        options.scale = 2
        options.mapType = .standard
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        if coordinates.count >= 2 {
            var fitted = region(for: coordinates)
            fitted.span.latitudeDelta *= 1.35
            fitted.span.longitudeDelta *= 1.35
            options.region = fitted
        } else if let only = coordinates.first {
            options.region = MKCoordinateRegion(center: only, latitudinalMeters: 3_200, longitudinalMeters: 3_200)
        } else {
            options.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 25.2854, longitude: 51.5310),
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            )
        }

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            return drawRoute(on: snapshot, coordinates: coordinates, trackyMood: trackyMood)
        } catch {
            print("[TripShare] snapshot fallback failed: \(error)")
            return nil
        }
    }

    private static func drawAspectFill(_ image: UIImage, in rect: CGRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            image.draw(in: rect)
            return
        }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2
        )
        image.draw(in: CGRect(origin: origin, size: drawSize))
    }

    private static func drawRoute(
        on snapshot: MKMapSnapshotter.Snapshot,
        coordinates: [CLLocationCoordinate2D],
        trackyMood: TrackyMood
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size, format: format)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            guard let start = coordinates.first else { return }
            let end = coordinates.last ?? start

            if coordinates.count >= 2 {
                let path = UIBezierPath()
                for (index, coordinate) in coordinates.enumerated() {
                    let point = snapshot.point(for: coordinate)
                    if index == 0 { path.move(to: point) }
                    else { path.addLine(to: point) }
                }

                // One confident stroke — not a glow sandwich
                lime.withAlphaComponent(0.35).setStroke()
                path.lineWidth = 14
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()

                lime.setStroke()
                path.lineWidth = 5
                path.stroke()
            }

            drawStartPin(at: snapshot.point(for: start))
            drawTrackyEnd(at: snapshot.point(for: end), mood: trackyMood)
        }
    }

    private static func drawStartPin(at point: CGPoint) {
        let diameter: CGFloat = 32
        let rect = CGRect(
            x: point.x - diameter / 2,
            y: point.y - diameter / 2,
            width: diameter,
            height: diameter
        )

        UIColor.black.withAlphaComponent(0.35).setFill()
        UIBezierPath(ovalIn: rect.offsetBy(dx: 0, dy: 2)).fill()

        lime.setFill()
        UIBezierPath(ovalIn: rect).fill()

        UIColor.white.withAlphaComponent(0.9).setStroke()
        let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        ring.lineWidth = 2.5
        ring.stroke()

        let symbol = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        if let play = UIImage(systemName: "play.fill", withConfiguration: symbol)?
            .withTintColor(UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1), renderingMode: .alwaysOriginal) {
            let size = play.size
            play.draw(in: CGRect(
                x: point.x - size.width / 2 + 1,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            ))
        }
    }

    /// Small Tracky at the finish — co-pilot, not a giant sticker.
    private static func drawTrackyEnd(at point: CGPoint, mood: TrackyMood) {
        let face: CGFloat = 52
        let disc: CGFloat = 58
        let assetName = mood == .locked ? "tracky-chill" : "tracky-\(mood.rawValue)"
        let faceImage = UIImage(named: assetName) ?? UIImage(named: "tracky-chill")

        let discRect = CGRect(
            x: point.x - disc / 2,
            y: point.y - disc / 2,
            width: disc,
            height: disc
        )

        UIColor.black.withAlphaComponent(0.4).setFill()
        UIBezierPath(ovalIn: discRect.offsetBy(dx: 0, dy: 3)).fill()

        UIColor.black.withAlphaComponent(0.55).setFill()
        UIBezierPath(ovalIn: discRect).fill()

        if let faceImage {
            let faceRect = CGRect(
                x: point.x - face / 2,
                y: point.y - face / 2,
                width: face,
                height: face
            )
            let ctx = UIGraphicsGetCurrentContext()
            ctx?.saveGState()
            UIBezierPath(ovalIn: faceRect).addClip()
            faceImage.draw(in: faceRect)
            ctx?.restoreGState()
        }

        UIColor.white.withAlphaComponent(0.9).setStroke()
        let ring = UIBezierPath(ovalIn: discRect.insetBy(dx: 1, dy: 1))
        ring.lineWidth = 2.5
        ring.stroke()

        // Tiny lime accent ring so Tracky reads as the finish
        lime.withAlphaComponent(0.85).setStroke()
        let accent = UIBezierPath(ovalIn: discRect.insetBy(dx: -3, dy: -3))
        accent.lineWidth = 2
        accent.stroke()
    }

    private static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0
        let maxLng = lngs.max() ?? 0
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.55, 0.018),
                longitudeDelta: max((maxLng - minLng) * 1.55, 0.018)
            )
        )
    }

    private static func placeholderMap(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.07, green: 0.09, blue: 0.08, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Copy

    private static func shareCaption(trip: Trip, vehicleName: String) -> String {
        let when = trip.startedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let name = vehicleName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return when }
        return "\(name) · \(when)"
    }

    private static func distanceParts(_ km: Double, unit: String) -> (value: String, unit: String) {
        if unit == "mi" {
            let mi = km * 0.621371
            return (String(format: mi >= 100 ? "%.0f" : "%.1f", mi), "mi")
        }
        return (String(format: km >= 100 ? "%.0f" : "%.1f", km), "km")
    }

    private static func heroPointSize(for value: String) -> CGFloat {
        switch value.count {
        case 0...2: return 280
        case 3: return 240
        case 4: return 200
        default: return 168
        }
    }

    private static func boldFont(size: CGFloat) -> UIFont {
        UIFont(name: "SpaceGrotesk-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    private static func mediumFont(size: CGFloat) -> UIFont {
        UIFont(name: "SpaceGrotesk-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    }
}

/// Presents the system share sheet for images / items.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
