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
final class HexColorStore {
    
    // MARK: - Storage
    
    /// Sparse color storage: H3 cell ID → UIColor
    ///
    /// This is a simple in-memory dictionary for now. In production, this will:
    /// - Sync with server state
    /// - Persist to disk for offline viewing
    private var colors: [UInt64: UIColor] = [:]
    private let queue = DispatchQueue(label: "com.territorial.hexColorStore", qos: .userInitiated)
    
    // MARK: - System Color Palette
    
    /// Available system colors for demo purposes
    ///
    /// These are UIKit's semantic colors that adapt to light/dark mode automatically.
    /// In production, these will be replaced by team colors from the game design:
    /// - 7 team colors (one per team)
    /// - Contested state color (likely gray or pulsing)
    /// - Unclaimed state (transparent or very faint)
    private static let systemColors: [UIColor] = [
        .systemRed,
        .systemBlue,
        .systemGreen,
        .systemOrange,
        .systemPurple,
        .systemPink,
        .systemTeal,
        .systemIndigo,
        .systemYellow,
        .systemBrown,
        .systemCyan,
        .systemMint
    ]
    
    // MARK: - Public Interface
    
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
        queue.sync {
            // If we already have a color, return it
            if let existingColor = colors[hexID] {
                return existingColor
            }
            
            // DEMO: Assign random color
            // PRODUCTION: This will be replaced by:
            // 1. Fetch from server state if resolution 10
            // 2. Aggregate from children if lower resolution
            let newColor = Self.systemColors.randomElement() ?? .systemBlue
            colors[hexID] = newColor
            return newColor
        }
    }
    
    /// Set color for a specific hexagon
    ///
    /// PRODUCTION USE:
    /// This will be called when:
    /// - Receiving map delta updates from server
    /// - Processing tick results
    /// - Syncing initial map state
    ///
    /// - Parameters:
    ///   - color: UIColor to assign
    ///   - hexID: H3 cell ID (UInt64)
    func setColor(_ color: UIColor, for hexID: UInt64) {
        queue.async(flags: .barrier) {
            self.colors[hexID] = color
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
            self.colors.removeValue(forKey: hexID)
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
    /// - Parameter updates: Dictionary of hexID → UIColor changes
    func updateColors(_ updates: [UInt64: UIColor]) {
        queue.async(flags: .barrier) {
            self.colors.merge(updates) { _, new in new }
        }
    }
    
    /// Get all currently stored colors (for debugging/testing)
    ///
    /// - Returns: Snapshot of current color state
    func allColors() -> [UInt64: UIColor] {
        queue.sync {
            return colors
        }
    }
    
    /// Clear all colors (for reset/testing)
    func clear() {
        queue.async(flags: .barrier) {
            self.colors.removeAll()
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

// MARK: - Future Team Color Mapping

/// PLACEHOLDER: Team colors for production game
///
/// Per game design, there are 7 teams. This enum will map team IDs to colors.
/// Colors should be:
/// - Visually distinct
/// - Colorblind-friendly
/// - Work in both light and dark mode
///
/// Contested state needs a special color (neutral gray or pulsing effect)
enum TeamColor {
    // TODO: Define team color palette
    // case team1, team2, team3, team4, team5, team6, team7
    // case contested
    // case unclaimed
    
    // var uiColor: UIColor { ... }
}
