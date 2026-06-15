// ZendDropWidget.swift
// Zend Drop — iOS Home Screen Widget
//
// NOTE: This file lives in the ZendDropWidget/ directory.
// To fully wire this Widget Extension into the app, you must add a new
// "Widget Extension" target in Xcode manually:
//   1. File → New → Target → Widget Extension
//   2. Name it "ZendDropWidget"
//   3. Set the bundle identifier to $(PRODUCT_BUNDLE_IDENTIFIER).ZendDropWidget
//   4. Point the target's source files at this directory
//   5. Add the target to the Runner app's "Embed App Extensions" build phase
//   6. In the extension target's Info.plist, set NSExtensionPrincipalClass to
//      $(PRODUCT_MODULE_NAME).ZendDropWidget
//
// Requirements: 7.1

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Entry

struct DropWidgetEntry: TimelineEntry {
    let date: Date
    let isAdvertising: Bool
    let secondsRemaining: Int
}

// MARK: - Timeline Provider

struct DropWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DropWidgetEntry {
        DropWidgetEntry(date: Date(), isAdvertising: false, secondsRemaining: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (DropWidgetEntry) -> Void) {
        completion(DropWidgetEntry(date: Date(), isAdvertising: false, secondsRemaining: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DropWidgetEntry>) -> Void) {
        let entry = DropWidgetEntry(date: Date(), isAdvertising: false, secondsRemaining: 0)
        // Static timeline — widget state is driven by App Intent actions, not polling.
        // DropBeaconIntent will call WidgetCenter.shared.reloadTimelines(ofKind: "ZendDropWidget")
        // after toggling advertising state.
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// MARK: - Widget View

struct ZendDropWidgetEntryView: View {
    var entry: DropWidgetEntry

    var body: some View {
        ZStack {
            Color(red: 0.071, green: 0.125, blue: 0.094) // ZendColors.bgDeep

            VStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 24))
                    .foregroundColor(Color(red: 0.322, green: 0.718, blue: 0.533)) // accentBright

                Button(intent: DropBeaconIntent()) {
                    Text(entry.isAdvertising ? "Discoverable" : "Be Discoverable")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Configuration

@main
struct ZendDropWidget: Widget {
    let kind: String = "ZendDropWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DropWidgetProvider()) { entry in
            ZendDropWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Zend Drop")
        .description("Tap to receive nearby payments instantly.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
