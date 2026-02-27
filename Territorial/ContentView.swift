//
//  ContentView.swift
//  Territorial
//
//  Created by Jacob Germana-McCray on 2/16/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Map", systemImage: "globe.americas.fill") {
                HexMapView().ignoresSafeArea()
            }
            
            Tab("Overview", systemImage: "newspaper.fill") {
                EmptyView()
            }
            
            Tab("Profile", systemImage: "person.fill") {
                EmptyView()
            }
        }
        
    }
}

#Preview {
    ContentView()
}
