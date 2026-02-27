//
//  HexOverlay.swift
//  Territorial
//
//  Created by Jacob Germana-McCray on 2/16/26.
//

import MapKit

/// MapKit overlay that represents the H3 hexagonal grid with per-hex coloring
///
/// ARCHITECTURE:
/// This class acts as the data model for the hex grid overlay.
/// It's the bridge between:
/// - MapViewController (which computes which hexes are visible)
/// - HexOverlayRenderer (which draws the hexes)
/// - HexColorStore (which manages hex colors)
///
/// MKOVERLAY PROTOCOL:
/// MKOverlay requires:
/// - coordinate: A representative coordinate for the overlay
/// - boundingMapRect: The area covered by the overlay
final class HexOverlay: NSObject, MKOverlay {
    
    /// Representative coordinate for the overlay
    var coordinate: CLLocationCoordinate2D
    
    /// Bounding rectangle for the overlay
    var boundingMapRect: MKMapRect
    
    /// Color storage for all hexagons
    let colorStore = HexColorStore()
    
    private let boundaryQueue = DispatchQueue(
        label: "com.territorial.boundaries",
        attributes: .concurrent
    )
    
    /// Sparse storage: H3 index → boundary coordinates
    /// This is updated in real-time as the user pans/zooms the map.
    /// MapViewController manages adding/removing entries.
    private var _boundaries: [UInt64: [CLLocationCoordinate2D]] = [:]

    var boundaries: [UInt64: [CLLocationCoordinate2D]] {
        boundaryQueue.sync { _boundaries }
    }

    func setBoundary(_ coords: [CLLocationCoordinate2D], for hexID: UInt64) {
        boundaryQueue.async(flags: .barrier) { self._boundaries[hexID] = coords }
    }

    func removeBoundary(for hexID: UInt64) {
        boundaryQueue.async(flags: .barrier) { self._boundaries.removeValue(forKey: hexID) }
    }
    
    
    // MARK: - Initialization
    
    /// Initialize overlay with a region
    ///
    /// - Parameter region: Initial map region (typically centered on user location)
    init(region: MKCoordinateRegion) {
        self.coordinate = region.center
        self.boundingMapRect = MKMapRect.world
        super.init()
    }
}
