//
//  HexOverlayRenderer.swift
//  Territorial
//
//  Created by Jacob Germana-McCray on 2/16/26.
//

import MapKit

/// Custom renderer for HexOverlay that draws colored hexagons batched by color
///
/// RENDERING PIPELINE:
/// 1. MapKit calls draw(_:zoomScale:in:) for the visible map rectangle
/// 2. We do a single grouping pass over overlay.boundaries:
///    - For each hex, look up its color and append its path into a per-color
///      CGMutablePath bucket
/// 3. We then do two submission passes over the K distinct color buckets:
///    a. Fill pass: one fillPath() call per color
///    b. Stroke pass: one strokePath() call per color
///
///
/// FUTURE PRODUCTION NOTES:
/// - Residual strength (from game design) can modulate the fill alpha per color group
/// - Contested state can be a separate color bucket drawn with a different alpha
/// - A pulsing contested effect would require CADisplayLink + setNeedsDisplay cycling,
///   not a Core Graphics technique
final class HexOverlayRenderer: MKOverlayRenderer {

    // MARK: - Drawing

    override func draw(_ mapRect: MKMapRect,
                       zoomScale: MKZoomScale,
                       in context: CGContext) {

        guard let overlay = overlay as? HexOverlay else { return }

        // ─────────────────────────────────────────────────────────────────
        // PASS 1 — Geometry grouping (pure CPU, zero rasterization cost)
        //
        // We build one CGMutablePath per distinct UIColor. UIColor system
        // singletons (e.g. .systemRed) satisfy reference equality in a
        // Dictionary, so this grouping is correct for our fixed palette.
        //
        // WHY CGMutablePath instead of [CGPath]:
        // CGMutablePath is a mutable, appendable path object. We can keep
        // adding subpaths (each hex polygon) to the same instance, and Core
        // Graphics treats the whole thing as one compound shape at fill time.
        // ─────────────────────────────────────────────────────────────────
        var fillPaths:   [UIColor: CGMutablePath] = [:]
        var strokePaths: [UIColor: CGMutablePath] = [:]

        for (hexID, coords) in overlay.boundaries {
            guard let first = coords.first else { continue }

            // Build the hex polygon path (coordinate → screen point conversion)
            let hexPath = CGMutablePath()
            hexPath.move(to: point(for: MKMapPoint(first)))
            for coord in coords.dropFirst() {
                hexPath.addLine(to: point(for: MKMapPoint(coord)))
            }
            hexPath.closeSubpath()

            let hexColor = overlay.colorStore.color(for: hexID)

            // Append this hex into the correct color bucket.
            //
            // Dictionary subscript with a default value returns an existing
            // entry or creates a new CGMutablePath inline — idiomatic Swift.
            // We then must write back because subscript gives us a copy.
            //
            // WHY TWO SEPARATE DICTIONARIES (fill vs stroke):
            // Fill alpha (0.35) and stroke alpha (0.5) differ. We need to
            // set the color separately for each pass. Keeping two dictionaries
            // avoids recalculating which hexes belong to which color at stroke
            // time — both are built in the same loop iteration.
            let existingFill = fillPaths[hexColor] ?? CGMutablePath()
            existingFill.addPath(hexPath)
            fillPaths[hexColor] = existingFill

            let existingStroke = strokePaths[hexColor] ?? CGMutablePath()
            existingStroke.addPath(hexPath)
            strokePaths[hexColor] = existingStroke
        }

        // ─────────────────────────────────────────────────────────────────
        // PASS 2a — Fill submission (1 rasterization call per color group)
        //
        // context.addPath() queues the geometry.
        // context.fillPath() is the actual rasterization submit.
        //
        // The fill rule here is .winding (default). Since adjacent hexes in
        // the compound path don't overlap, winding vs evenOdd makes no
        // difference in practice. If hexes ever share boundary points due to
        // floating-point edge cases, .evenOdd would be safer.
        // ─────────────────────────────────────────────────────────────────
        for (color, path) in fillPaths {
            context.addPath(path)
            
            let alpha = if color == UIColor.clear {
                0.0
            } else {
                0.25
            }
            context.setFillColor(color.withAlphaComponent(alpha).cgColor)
            context.fillPath()
        }

        // ─────────────────────────────────────────────────────────────────
        // PASS 2b — Stroke submission (1 rasterization call per color group)
        //
        // Line width is divided by zoomScale so borders remain visually
        // consistent regardless of zoom level — a point at zoom 1 would be
        // a hair-thin line at zoom 4 otherwise.
        // ─────────────────────────────────────────────────────────────────
        context.setLineWidth(0.5 / zoomScale)
        for (color, path) in strokePaths {
            context.addPath(path)
            context.setStrokeColor(color.withAlphaComponent(0.5).cgColor)
            context.strokePath()
        }
    }

    // MARK: - Cache Invalidation

    /// Tell MapKit to discard its cached tile and call draw(_:zoomScale:in:) again.
    ///
    /// Must be called on the main thread. MapViewController is responsible for
    /// dispatching to main when invoking this after background state changes.
    func invalidatePath() {
        setNeedsDisplay()
    }
}
