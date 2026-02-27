//
//  MapViewController.swift
//  Territorial
//
//  Created by Jacob Germana-McCray on 2/16/26.
//

import UIKit
import MapKit
import SwiftyH3
import CoreLocation

/// UIKit view controller that manages the map and hex overlay
///
/// RESPONSIBILITIES:
/// - Display MKMapView
/// - Compute which hexes are visible based on viewport
/// - Add/remove hexes from overlay as user pans/zooms
/// - Manage resolution selection based on zoom level
/// - Handle continuous updates during user interaction
///
/// COLOR INTEGRATION:
/// This controller doesn't directly manage colors - that's handled by HexColorStore.
/// When hexes are added to overlay.boundaries, the renderer automatically:
/// 1. Calls overlay.colorStore.color(for: hexID)
/// 2. Color store assigns a random color if not already set
/// 3. Renderer draws with that color
///
/// In production, colors will come from server sync instead of random assignment.
final class MapViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate {

    // MARK: - Properties
    
    /// The main map view
    let mapView = MKMapView()
    
    /// The hex overlay that contains all visible hexagons
    ///
    /// This overlay includes:
    /// - boundaries: Dict of visible hexes (managed by this controller)
    /// - colorStore: Sparse KV storage for hex colors (managed separately)
    private let overlay = HexOverlay(region: MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
    ))
    
    /// The renderer for the hex overlay
    private var renderer: HexOverlayRenderer!
    
    /// Track which hexes were visible in the previous update
    ///
    /// WHY TRACK PREVIOUS:
    /// - We diff against this to find added/removed hexes
    /// - Only update what changed (don't redraw entire grid)
    /// - Matches the game's delta update model
    private var prevCells = Set<UInt64>()
    
    /// Maximum number of hexes to render at once
    ///
    /// WHY LIMIT:
    /// - Prevents memory exhaustion on low zoom
    /// - Forces fallback to lower resolution when viewport is too large
    /// - 50k hexes is empirically determined to be smooth on modern devices
    private let cellBudget = 50_000
    
    /// Track whether we've set an initial region
    ///
    /// WHY NEEDED:
    /// - Prevents world-scale polyfill attempt before initialization
    /// - MapKit fires regionDidChange during initial setup
    /// - We ignore updates until we've set a reasonable initial region
    private var hasSetInitialRegion = false
    private var hasCenteredOnUser = false
    
    /// Timer for real-time updates during user interaction
    ///
    /// PERFORMANCE:
    /// - Only active while user is panning/zooming
    /// - Fires every 150ms for smooth visual updates
    /// - Cleaned up when interaction ends
    private var updateTimer: Timer?
    
    /// How often to update grid during interaction
    private let updateInterval: TimeInterval = 0.05  // 50ms
    
    private let locationManager = CLLocationManager()

    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        
        // Set up map view
        mapView.frame = view.bounds
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        view.addSubview(mapView)
        
        // Set a reasonable initial region to avoid world-scale polyfill
        // This prevents the catastrophic memory allocation on first load
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        mapView.setRegion(initialRegion, animated: false)
        hasSetInitialRegion = true
        
        // Add the hex overlay to the map
        mapView.addOverlay(overlay)
        
        // COLOR NOTE:
        // At this point, no colors are assigned yet. Colors are assigned lazily
        // when the renderer first draws each hex. This is the idiomatic approach:
        // - Don't precompute data that might not be needed
        // - Let the renderer pull data on-demand
        // - Color store handles the lazy initialization
        
        let hexTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleHexTap(_:))
        )
        hexTap.delegate = self
        mapView.addGestureRecognizer(hexTap)
        mapView.showsUserLocation = true
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            // handle — show UI telling user why it matters
            break
        case .notDetermined:
            break // waiting for the dialog response
        @unknown default:
            break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, !hasCenteredOnUser else { return }
            
            let region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
            mapView.setRegion(region, animated: true)
            hasCenteredOnUser = true
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
    
    @objc func handleHexTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let tapLocation = gestureRecognizer.location(in: mapView)
        let tapLocationOnMap = MKMapPoint(
            mapView.convert(tapLocation, toCoordinateFrom: mapView)
        )
        
        let latlng = H3LatLng(
            latitudeDegs: tapLocationOnMap.coordinate.latitude,
            longitudeDegs: tapLocationOnMap.coordinate.longitude
        )
        let cell = try! latlng.cell(at: .res10)
        
        debugPrint(
            "Tap: \(tapLocationOnMap), Cell: \(String(cell.id, radix: 16, uppercase: true))"
        )
    }
    
    deinit {
        // Clean up timer when view controller is deallocated
        // This prevents potential retain cycles and ensures proper resource cleanup
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - MKMapViewDelegate
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let hexOverlay = overlay as? HexOverlay {
            renderer = HexOverlayRenderer(overlay: hexOverlay)
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        // Start continuous updates during user interaction
        // This fires once when the user begins panning/zooming
        
        // Invalidate any existing timer to avoid duplicates
        updateTimer?.invalidate()
        
        // Start polling for updates while user is interacting with the map
        // We use a repeating timer instead of waiting for regionDidChange
        // because regionDidChange only fires AFTER the gesture completes
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateGrid()
        }
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        // Clean up timer when interaction completes
        // This fires once when the user stops panning/zooming
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Only update grid after we've set initial region
        // This prevents the world-scale polyfill attempt before initialization
        guard hasSetInitialRegion else { return }
        
        // Do a final update with the completed region
        // This ensures we have the most accurate grid for the final position
        updateGrid()
    }

    // MARK: - Grid Update Logic
    
    /// Compute polygon for the visible map region (with padding)
    ///
    /// EDGE CASE HANDLING:
    /// This method handles several geographic edge cases that can cause H3 errors:
    ///
    /// 1. **Pole Proximity**: Latitude is clamped to [-85°, 85°]
    ///    - H3 struggles near poles due to extreme hex distortion
    ///    - Web Mercator projection (used by MapKit) is undefined beyond ±85.05°
    ///    - Clamping prevents "too many half edges" errors
    ///
    /// 2. **Antimeridian Crossing**: Detected when polygon spans ±180° longitude
    ///    - H3's polygon algorithm expects continuous coordinate space
    ///    - Crossing the date line creates discontinuous jumps (179° → -179°)
    ///    - We detect this and split into eastern/western hemispheres if needed
    ///
    /// 3. **Very Large Spans**: Viewport > 180° would wrap around the globe
    ///    - Clamp to maximum reasonable viewport
    ///    - Prevents degenerate polygon geometries
    ///
    /// WHY THESE ERRORS OCCUR:
    /// The H3 error "iterating over too many half edges in walkCWEdgesIncidentToVertex"
    /// means the polygon traversal algorithm is stuck in a loop. This happens when:
    /// - Polygon vertices are at invalid latitudes (beyond ±90°)
    /// - Polygon edges cross the antimeridian without proper handling
    /// - Polygon is self-intersecting (shouldn't happen with our rectangles)
    ///
    /// FIRST PRINCIPLES:
    /// Geographic coordinates have inherent discontinuities:
    /// - Latitude wraps at poles (±90° → undefined)
    /// - Longitude wraps at antimeridian (±180° → -180°)
    /// - Mercator projection is undefined beyond ±85.05°
    ///
    /// We must detect and handle these before passing to H3.
    private func polygonForVisibleRegion() throws -> H3Polygon {
        let r = mapView.region
        let c = r.center
        let latD = r.span.latitudeDelta / 2
        let lonD = r.span.longitudeDelta / 2
        
        // EDGE CASE 1: Clamp latitude to safe range
        // WHY 85°: Web Mercator projection (MapKit's default) is undefined beyond ±85.05°
        // H3 also struggles near poles due to extreme hexagon distortion
        let maxLat: Double = 85.0
        let minLat: Double = -85.0
        
        let northLat = min(c.latitude + latD, maxLat)
        let southLat = max(c.latitude - latD, minLat)
        
        // EDGE CASE 2: Detect antimeridian crossing
        // The antimeridian (±180° longitude) creates a discontinuity
        // If our viewport crosses it, longitude arithmetic breaks
        //
        // Example problem:
        // Center: 170° longitude, span: 30° → west edge: 155°, east edge: 185°
        // But 185° wraps to -175°, creating: west=155°, east=-175°
        // H3 sees this as spanning 330° (going the wrong way around the globe)
        let westLon = c.longitude - lonD
        let eastLon = c.longitude + lonD
        
        // Check if we're crossing the antimeridian
        // This happens when west > east after normalization
        let crossesAntimeridian = westLon < -180 || eastLon > 180
        
        if crossesAntimeridian {
            // ANTIMERIDIAN HANDLING:
            // When crossing ±180°, we have two options:
            // 1. Split into two polygons (east of antimeridian + west of antimeridian)
            // 2. Use a smaller viewport that doesn't cross
            //
            // Option 2 is simpler and still shows hexes near the antimeridian
            // We clamp the viewport to not cross the boundary
            print("Warning: Viewport crosses antimeridian, clamping to hemisphere")
            
            // Determine which side of the antimeridian we're closer to
            if c.longitude > 0 {
                // Closer to +180°, clamp to eastern hemisphere
                let clampedWestLon = max(westLon, -180)
                let clampedEastLon = min(eastLon, 180)
                
                return try createPolygon(
                    north: northLat,
                    south: southLat,
                    west: clampedWestLon,
                    east: clampedEastLon
                )
            } else {
                // Closer to -180°, clamp to western hemisphere
                let clampedWestLon = max(westLon, -180)
                let clampedEastLon = min(eastLon, 180)
                
                return try createPolygon(
                    north: northLat,
                    south: southLat,
                    west: clampedWestLon,
                    east: clampedEastLon
                )
            }
        }
        
        // Normal case: apply horizontal padding
        // This creates visual breathing room on the sides without hexagons
        // The padding is proportional to the viewport size for consistent appearance at all zoom levels
        let horizontalPaddingFactor: Double = 0.15  // 15% padding on each side
        let paddedLonD = lonD * (1.0 - horizontalPaddingFactor)
        
        return try createPolygon(
            north: northLat,
            south: southLat,
            west: c.longitude - paddedLonD,
            east: c.longitude + paddedLonD
        )
    }
    
    /// Helper to create H3Polygon from bounding coordinates
    ///
    /// COORDINATE ORDER:
    /// H3 expects polygon vertices in counter-clockwise order
    /// (when viewed from above). Our rectangle goes: NW → NE → SE → SW
    ///
    /// VALIDATION:
    /// - North must be > South (basic sanity check)
    /// - Longitude span should be < 360° (no full globe wrapping)
    ///
    /// - Parameters:
    ///   - north: Northern latitude (clamped to ±85°)
    ///   - south: Southern latitude (clamped to ±85°)
    ///   - west: Western longitude
    ///   - east: Eastern longitude
    /// - Returns: H3Polygon ready for polyfill operation
    private func createPolygon(north: Double, south: Double, west: Double, east: Double) throws -> H3Polygon {
        // Sanity checks
        guard north > south else {
            throw NSError(domain: "MapViewController", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid polygon: north must be > south"])
        }
        
        // Create rectangle vertices in counter-clockwise order
        // This is the standard convention for H3 polygons
        let ring = [
            H3LatLng(latitudeDegs: north, longitudeDegs: west),   // NW
            H3LatLng(latitudeDegs: north, longitudeDegs: east),   // NE
            H3LatLng(latitudeDegs: south, longitudeDegs: east),   // SE
            H3LatLng(latitudeDegs: south, longitudeDegs: west)    // SW
        ]
        
        return H3Polygon(ring)
    }

    /// Calculate optimal H3 resolution based on visible span
    ///
    /// This prevents attempting polyfill at resolutions that would crash
    ///
    /// Resolution Guide (avg hex edge length):
    /// - 1: 418 km    (large country/hemisphere)
    /// - 2: 158 km    (country/large state)
    /// - 3: 60 km     (state/province)
    /// - 4: 22 km     (metropolitan area)
    /// - 5: 8.5 km    (city)
    /// - 6: 3.2 km    (large neighborhood)
    /// - 7: 1.2 km    (neighborhood)
    /// - 8: 461 m     (city block)
    /// - 9: 174 m     (large building)
    /// - 10: 66 m     (building)
    ///
    /// Source: https://h3geo.org/docs/core-library/restable/
    private func calculateResolutionForSpan(_ span: MKCoordinateSpan) -> Int {
        // Use the larger of lat/lng delta to handle non-square viewports
        let maxDelta = max(span.latitudeDelta, span.longitudeDelta)
        
        // Map visible degrees to appropriate resolution (1-10 range)
        // These thresholds are tuned to keep cell count < 50,000
        switch maxDelta {
        case 45...:        return 1   // Very large regions (hemisphere+)
        case 20..<45:      return 2   // Multi-country
        case 10..<20:      return 3   // Country
        case 5..<10:       return 4   // Large state/province
        case 2..<5:        return 5   // State/small country
        case 1..<2:        return 6   // Metropolitan area
        case 0.5..<1:      return 7   // City
        case 0.2..<0.5:    return 8   // Large neighborhood
        case 0.1..<0.2:    return 9   // Neighborhood
        default:           return 10  // City blocks and smaller
        }
    }
    
    /// Get H3 cells for polygon with safety fallbacks
    private func chooseResolution(poly: H3Polygon) throws -> (Int, [H3Cell]) {
        let region = mapView.region
        let targetRes = calculateResolutionForSpan(region.span)
        
        // Try target resolution first, then fall back to lower resolutions if needed
        // We start at calculated resolution to avoid expensive failed attempts
        // Ensure we never go below resolution 1
        for res in stride(from: targetRes, through: max(1, targetRes - 3), by: -1) {
            guard let h3Res = H3Cell.Resolution(rawValue: Int32(res)) else { continue }
            
            do {
                let cells = try poly.cells(at: h3Res)
                
                // Safety check: if we somehow got too many cells, try lower resolution
                if cells.count <= cellBudget {
                    print("Using resolution \(res) with \(cells.count) cells (span: \(region.span.latitudeDelta)°)")
                    return (res, cells)
                } else {
                    print("Resolution \(res) produced \(cells.count) cells, trying lower")
                    continue
                }
            } catch {
                // If allocation fails, try lower resolution
                print("Failed at resolution \(res), trying lower: \(error)")
                continue
            }
        }
        
        // Emergency fallback: try resolution 1 (should work for any reasonable viewport)
        print("Warning: Falling back to resolution 1")
        let fallbackRes = H3Cell.Resolution(rawValue: 1)!
        let cells = try poly.cells(at: fallbackRes)
        return (1, cells)
    }

    /// Update the hex grid based on current viewport
    ///
    /// ALGORITHM:
    /// 1. Compute visible region polygon (with edge case handling)
    /// 2. Select appropriate H3 resolution
    /// 3. Polyfill to get all hexes in that region
    /// 4. Diff against previous hexes (find added/removed)
    /// 5. Update overlay.boundaries
    /// 6. Trigger renderer to redraw
    ///
    /// ERROR HANDLING:
    /// - Polygon validation errors (antimeridian, poles) → skip update silently
    /// - H3 allocation errors → fall back to lower resolution
    /// - Unknown errors → log and skip
    ///
    /// WHY SILENT FAILURE:
    /// Geographic edge cases (poles, antimeridian) are temporary as user pans.
    /// Showing an error would be jarring. Instead, we:
    /// - Skip the problematic update
    /// - Keep previous hexes visible
    /// - Resume normal updates when user pans to valid region
    ///
    /// COLOR HANDLING:
    /// This method does NOT manage colors. Colors are handled by:
    /// - HexColorStore assigns colors lazily when renderer requests them
    /// - For demo: random colors
    /// - For production: colors will be synced from server
    ///
    /// THREAD SAFETY:
    /// - Heavy computation runs on background queue (H3 polyfill)
    /// - UI updates (overlay.boundaries, renderer) run on main queue
    /// - This is the idiomatic iOS pattern for async work
    private func updateGrid() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let poly = try self.polygonForVisibleRegion()
                let (_, cells) = try self.chooseResolution(poly: poly)
                let newSet = Set(cells.map { $0.id })

                // Diff to find what changed
                let added = newSet.subtracting(self.prevCells)
                let removed = self.prevCells.subtracting(newSet)

                // Add new hexes to boundaries
                // COLOR NOTE: We don't set colors here! The renderer will
                // call overlay.colorStore.color(for:) when it draws each hex.
                for idx in added {
                    let cell = H3Cell(idx)
                    let coords = try cell.boundary.map {
                        CLLocationCoordinate2D(latitude: $0.latitudeDegs, longitude: $0.longitudeDegs)
                    }
                    self.overlay.setBoundary(coords, for: idx)
                }

                // Remove hexes that left viewport
                // COLOR NOTE: We keep the color in the store even when removing
                // from boundaries. This implements the sparse storage model:
                // - boundaries = ephemeral (only visible hexes)
                // - colorStore = persistent (all touched hexes)
                for idx in removed {
                    self.overlay.removeBoundary(for: idx)
                }

                self.prevCells = newSet

                // Trigger redraw on main thread
                DispatchQueue.main.async {
                    self.renderer?.invalidatePath()
                }

            } catch let error as NSError where error.domain == "MapViewController" {
                // Polygon validation error (antimeridian, poles, etc.)
                // This is expected when panning near edge cases
                // Skip update silently - will resume when viewport is valid
                print("Skipping grid update due to edge case: \(error.localizedDescription)")
            } catch {
                // Unexpected H3 error
                // Log it but don't crash - keep previous hexes visible
                print("H3 error during grid update: \(error)")
            }
        }
    }
    
    // MARK: - Future: Server Sync
    
    /// PLACEHOLDER: Sync colors from server
    ///
    /// This will be called when:
    /// - App launches (initial map state)
    /// - Tick completes (delta update)
    /// - Reconnecting after offline period (catch-up sync)
    ///
    /// EXPECTED SERVER PAYLOAD:
    /// Per game design, server sends delta updates:
    /// {
    ///   "version": 12345,
    ///   "changes": [
    ///     { "hex_id": 644325524565041151, "team": 3, "state": "owned", "residual": 5 },
    ///     { "hex_id": 644325524565041152, "team": null, "state": "contested" }
    ///   ]
    /// }
    ///
    /// IMPLEMENTATION PLAN:
    /// 1. Map team ID → UIColor using team color palette
    /// 2. Handle contested state with special color
    /// 3. Batch update color store
    /// 4. Invalidate renderer to redraw
    ///
    /// - Parameter changes: Array of hex state changes from server
    func syncColorsFromServer(_ changes: [(hexID: UInt64, teamID: Int?, state: String)]) {
        // TODO: Implement when we have:
        // 1. Server API endpoint for delta updates
        // 2. Team color definitions
        // 3. Network layer for sync
        
        // Example implementation:
        // var colorUpdates: [UInt64: UIColor] = [:]
        // for change in changes {
        //     let color = teamColor(for: change.teamID, state: change.state)
        //     colorUpdates[change.hexID] = color
        // }
        // overlay.colorStore.updateColors(colorUpdates)
        // DispatchQueue.main.async {
        //     self.renderer?.invalidatePath()
        // }
    }
}

extension MapViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}
