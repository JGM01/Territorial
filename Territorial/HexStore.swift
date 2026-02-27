//
//  HexColorStore.swift
//  Territorial
//
//  Created by Jacob Germana-McCray on 2/16/26.
//

import UIKit

/// Sparse key-value store for hexagon colors indexed by H3 cell ID
/// Only touched tiles are stored in memory, matching the server's sparse KV store..
///
/// CURRENT STATE (Demo):
/// - Assigns random system colors to hexagons
/// - Stores colors at whatever resolution is currently being rendered
///
/// FUTURE STATE (Production):
/// - Resolution 10 cells will store team ownership colors
/// - Lower resolution cells will aggregate from their constituent level 10 cells
/// - Colors will sync from server state (owned/contested/unclaimed)
/// - Residual strength could affect color intensity
final class HexStore {
    
    // MARK: - Storage
    
    /// Sparse color storage: H3 cell ID → HexStatus
    ///
    /// This is a simple in-memory dictionary for now. In production, this will:
    /// - Sync with server state
    /// - Persist to disk for offline viewing
    private var hexToStatusMap: [UInt64: HexStatus] = [:]
    private let queue = DispatchQueue(label: "com.territorial.hexColorStore", qos: .userInitiated)
    
    /// Demo pool of team statuses (excludes contested/unclaimed)
    private static let demoTeamStatuses: [HexStatus] = [.red, .orange, .yellow, .green, .blue, .indigo, .purple]
    
    static let teamToColor: [HexStatus: UIColor] = [
        HexStatus.red: UIColor.red,
        HexStatus.orange: UIColor.orange,
        HexStatus.yellow: UIColor.yellow,
        HexStatus.green: UIColor.green,
        HexStatus.blue: UIColor.blue,
        HexStatus.indigo: UIColor.systemIndigo,
        HexStatus.purple: UIColor.purple,
        HexStatus.unclaimed: UIColor.clear,
        HexStatus.contested: UIColor.black
    ]

    
    // MARK: - Public Interface
    
    /// Get status for a hexagon, assigning a random team if not yet set (demo)
    /// - Parameter hexID: H3 cell ID (UInt64)
    /// - Returns: HexStatus for this hexagon
    func status(for hexID: UInt64) -> HexStatus {
        queue.sync {
            if let existing = hexToStatusMap[hexID] {
                return existing
            }
            let newStatus = Self.demoTeamStatuses.randomElement() ?? .blue
            hexToStatusMap[hexID] = newStatus
            return newStatus
        }
    }

    /// Get color for a hexagon, assigning a random color if not yet set
    ///
    /// DEMO BEHAVIOR:
    /// Returns a random system color for new cells
    ///
    /// PRODUCTION BEHAVIOR (future):
    /// - If cell is at resolution 10: return team color from ownership data
    /// - If cell is at lower resolution: aggregate colors from level 10 children
    /// - Use majority vote among child cells (matching game's vote aggregation logic)
    ///
    /// - Parameter hexID: H3 cell ID (UInt64)
    /// - Returns: UIColor for this hexagon
    func color(for hexID: UInt64) -> UIColor {
        let s = status(for: hexID)
        return Self.teamToColor[s] ?? .clear
    }
    
    /// Set status for a specific hexagon
    ///
    /// PRODUCTION USE:
    /// This will be called when:
    /// - Receiving map delta updates from server
    /// - Processing tick results
    /// - Syncing initial map state
    ///
    /// - Parameters:
    ///   - color: HexStatus to assign
    ///   - hexID: H3 cell ID (UInt64)
    func setColor(_ color: HexStatus, for hexID: UInt64) {
        queue.async(flags: .barrier) {
            self.hexToStatusMap[hexID] = color
        }
    }
    
    /// Remove color for a hexagon (sparse storage optimization)
    ///
    /// WHY REMOVE:
    /// - Sparse storage means we only keep active tiles
    /// - When a cell becomes unclaimed, we can delete its entry
    /// - Saves memory on inactive regions
    /// - Matches server's sparse KV model
    ///
    /// PRODUCTION USE:
    /// Called when tiles become neutral after long inactivity (months-scale per design doc)
    ///
    /// - Parameter hexID: H3 cell ID to remove
    func removeColor(for hexID: UInt64) {
        queue.async(flags: .barrier) {
            self.hexToStatusMap.removeValue(forKey: hexID)
        }
    }
    
    /// Bulk color update (for server sync)
    ///
    /// PRODUCTION USE:
    /// When receiving delta updates from server, we'll update many colors at once:
    /// - More efficient than individual setColor calls
    /// - Single queue transaction
    /// - Matches server's batch reducer output
    ///
    /// - Parameter updates: Dictionary of hexID → HexStatus changes
    func updateColors(_ updates: [UInt64: HexStatus]) {
        queue.async(flags: .barrier) {
            self.hexToStatusMap.merge(updates) { _, new in new }
        }
    }
    
    /// Get all currently stored colors (for debugging/testing)
    ///
    /// - Returns: Snapshot of current color state
    func allColors() -> [UInt64: UIColor] {
        queue.sync {
            var mapped: [UInt64: UIColor] = [:]
            for (key, status) in hexToStatusMap {
                mapped[key] = Self.teamToColor[status] ?? .clear
            }
            return mapped
        }
    }
    
    /// Clear all colors (for reset/testing)
    func clear() {
        queue.async(flags: .barrier) {
            self.hexToStatusMap.removeAll()
        }
    }
    
    // MARK: - Future: Aggregation Logic
    
    /// PLACEHOLDER: Compute aggregated color from level 10 children
    ///
    /// ALGORITHM (for future implementation):
    /// 1. Get all resolution 10 cells that fall within the parent hex
    /// 2. Count colors: [UIColor: Int]
    /// 3. Return the color with highest count (plurality wins, matching game rules)
    /// 4. Handle contested state: if tie, return contested color
    ///
    /// PERFORMANCE CONSIDERATIONS:
    /// - Cache aggregated results to avoid recomputation
    /// - Invalidate cache when any child's color changes
    /// - Consider precomputing for frequently viewed resolutions
    ///
    /// This is a stub for now - will be implemented when we have:
    /// - H3 hierarchy traversal (SwiftyH3 provides children(at:) method)
    /// - Server sync for resolution 10 ownership data
    /// - Team color definitions
    ///
    /// - Parameter hexID: Parent hex at lower resolution
    /// - Returns: Aggregated color from level 10 children
    func aggregatedColor(for hexID: UInt64) -> UIColor {
        // TODO: Implement once we have:
        // 1. Resolution 10 ownership data from server
        // 2. H3 hierarchy traversal to get children
        // 3. Team color mapping
        
        // For now, fall back to simple color lookup
        return color(for: hexID)
    }
}

/// There are 7 teams. This enum will map team IDs to colors.
enum HexStatus {
    case red, orange, yellow, green, blue, indigo, purple
    case contested
    case unclaimed
}
