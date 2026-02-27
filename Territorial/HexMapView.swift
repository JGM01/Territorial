//
//  HexMapView.swift
//  Territorial
//
//  Created by Jacob Germana-McCray on 2/16/26.
//

import SwiftUI
import MapKit

/// SwiftUI wrapper for MapViewController that displays an H3 hexagonal grid overlay
///
/// This view uses UIViewControllerRepresentable to bridge UIKit's MapViewController
/// into SwiftUI's declarative view hierarchy. The coordinator pattern is implemented
/// to handle future delegate callbacks or state synchronization.
struct HexMapView: UIViewControllerRepresentable {
    
    // MARK: - Bindable Properties
    
    // Future expansion: Add @Binding properties here for two-way data flow
    // Example: @Binding var selectedHexes: Set<UInt64>
    // Example: var initialRegion: MKCoordinateRegion
    
    // MARK: - UIViewControllerRepresentable Implementation
    
    /// Creates the coordinator that manages communication between SwiftUI and UIKit
    ///
    /// The Coordinator lives for the entire lifetime of the representable view
    /// and survives across view updates. It's the idiomatic place to:
    /// - Store delegate references
    /// - Handle callbacks from UIKit
    /// - Manage state that shouldn't trigger view updates
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    /// Creates the UIKit view controller (called once)
    ///
    /// This method is called once when the view first appears in the SwiftUI hierarchy.
    /// The created view controller is cached and reused across view updates.
    ///
    /// - Parameter context: Contains the coordinator and environment values
    /// - Returns: A fully configured MapViewController instance
    func makeUIViewController(context: Context) -> MapViewController {
        let viewController = MapViewController()
        
        // Future: Apply initial configuration from SwiftUI state
        // Example: viewController.mapView.region = initialRegion
        // Example: viewController.delegate = context.coordinator
        
        return viewController
    }
    
    /// Updates the UIKit view controller when SwiftUI state changes
    ///
    /// This method is called whenever SwiftUI determines the view needs to update
    /// (e.g., when @State, @Binding, or other dependencies change).
    ///
    /// IMPORTANT: This should only update properties that have actually changed.
    /// Avoid expensive operations here as this can be called frequently.
    ///
    /// - Parameters:
    ///   - uiViewController: The cached MapViewController instance
    ///   - context: Contains the coordinator and updated environment values
    func updateUIViewController(_ uiViewController: MapViewController, context: Context) {
        // Future: Synchronize SwiftUI state changes to UIKit
        // Example:
        // if uiViewController.selectedHexes != selectedHexes {
        //     uiViewController.updateSelection(selectedHexes)
        // }
        
        // Currently no-op since MapViewController has no configurable properties
        // from SwiftUI side
    }
    
    /// Optional cleanup when the view is removed from the hierarchy
    ///
    /// Use this to tear down expensive resources, cancel ongoing operations,
    /// or remove observers. SwiftUI calls this when the view is permanently
    /// removed (not just hidden).
    static func dismantleUIViewController(_ uiViewController: MapViewController, coordinator: Coordinator) {
        // Future: Cleanup operations
        // Example: uiViewController.stopLocationUpdates()
        // Example: coordinator.cancelPendingOperations()
    }
    
    // MARK: - Coordinator
    
    /// Coordinator manages the relationship between SwiftUI and UIKit
    ///
    /// The coordinator pattern is the idiomatic way to:
    /// - Act as a delegate for UIKit components
    /// - Bridge callbacks from UIKit back to SwiftUI
    /// - Store stateful references that shouldn't trigger view updates
    ///
    /// The coordinator has a stable identity across view updates, making it
    /// perfect for delegate conformance (delegates are typically weak references).
    class Coordinator: NSObject {
        var parent: HexMapView
        
        init(parent: HexMapView) {
            self.parent = parent
        }
        
        // Future: Add delegate methods here
        // Example:
        // func mapViewController(_ controller: MapViewController, didSelectHex: UInt64) {
        //     parent.selectedHexes.insert(didSelectHex)
        // }
    }
}

// MARK: - Preview Provider

#Preview("Default Map") {
    HexMapView()
}

#Preview("Full Screen") {
    HexMapView()
        .ignoresSafeArea()
}
