//
//  ContentView.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Today", systemImage: "chart.bar.fill")
                }
                .tag(0)
            
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(1)
            
            MyRecipesView()
                .tabItem {
                    Label("Recipes", systemImage: "book.closed.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [FoodItem.self, FoodLog.self])
}
