import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Attributes

@available(iOS 16.1, *)
struct DropActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var secondsRemaining: Int
        var receivedFrom: String?   // Set when a Drop is received
        var receivedAmount: String? // e.g. "10.00"
        var isPaused: Bool          // True when app leaves foreground
    }

    var zendtag: String // The Receiver's zendtag (shown in expanded view)
}

// MARK: - Live Activity Widget

@available(iOS 16.1, *)
struct DropLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DropActivityAttributes.self) { context in
            // Lock Screen / Notification banner view
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundColor(Color(red: 0.322, green: 0.718, blue: 0.533))

                if let sender = context.state.receivedFrom,
                   let amount = context.state.receivedAmount {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Received $\(amount) USDC")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("from @\(sender)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else if context.state.isPaused {
                    Text("Drop paused — open app to resume")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready to receive")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(timerString(context.state.secondsRemaining))
                            .font(.subheadline)
                            .foregroundColor(Color(red: 0.322, green: 0.718, blue: 0.533))
                            .monospacedDigit()
                    }
                }
                Spacer()
            }
            .padding()
            .background(Color(red: 0.071, green: 0.125, blue: 0.094))
            .activityBackgroundTint(Color(red: 0.071, green: 0.125, blue: 0.094))

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view (long-press)
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundColor(Color(red: 0.322, green: 0.718, blue: 0.533))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.secondsRemaining > 0 && !context.state.isPaused {
                        Text(timerString(context.state.secondsRemaining))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.gray)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let sender = context.state.receivedFrom,
                       let amount = context.state.receivedAmount {
                        VStack(spacing: 2) {
                            Text("Received $\(amount)")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("from @\(sender)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        Text("@\(context.attributes.zendtag) · Discoverable")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            } compactLeading: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundColor(Color(red: 0.322, green: 0.718, blue: 0.533))
                    .font(.caption)
            } compactTrailing: {
                if context.state.secondsRemaining > 0 {
                    Text(timerString(context.state.secondsRemaining))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(.gray)
                }
            } minimal: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundColor(Color(red: 0.322, green: 0.718, blue: 0.533))
                    .font(.caption2)
            }
        }
    }

    private func timerString(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Live Activity Manager

@available(iOS 16.1, *)
class DropLiveActivityManager {
    static let shared = DropLiveActivityManager()

    private var activity: Activity<DropActivityAttributes>?
    private var countdownTimer: Timer?

    func start(beacon: DropBeaconFetcher.BeaconResponse, durationSeconds: Int) {
        let attributes = DropActivityAttributes(zendtag: beacon.zendtag)
        let initialState = DropActivityAttributes.ContentState(
            secondsRemaining: durationSeconds,
            receivedFrom: nil,
            receivedAmount: nil,
            isPaused: false
        )

        do {
            activity = try Activity<DropActivityAttributes>.request(
                attributes: attributes,
                contentState: initialState,
                pushType: nil
            )
            startCountdown(from: durationSeconds)
        } catch {
            // Live Activities not available or activity limit reached
        }
    }

    func notifyReceived(senderZendtag: String, amountUsdc: String) {
        countdownTimer?.invalidate()
        guard let activity else { return }
        let updatedState = DropActivityAttributes.ContentState(
            secondsRemaining: 0,
            receivedFrom: senderZendtag,
            receivedAmount: amountUsdc,
            isPaused: false
        )
        Task {
            await activity.update(using: updatedState)
        }
    }

    func pause() {
        guard let activity else { return }
        Task {
            var state = activity.contentState
            let pausedState = DropActivityAttributes.ContentState(
                secondsRemaining: state.secondsRemaining,
                receivedFrom: state.receivedFrom,
                receivedAmount: state.receivedAmount,
                isPaused: true
            )
            await activity.update(using: pausedState)
        }
    }

    func end() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        Task {
            await activity?.end(dismissalPolicy: .immediate)
            activity = nil
        }
    }

    private func startCountdown(from seconds: Int) {
        var remaining = seconds
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            remaining -= 1
            guard let self = self, let activity = self.activity else {
                timer.invalidate()
                return
            }
            if remaining <= 0 {
                timer.invalidate()
                self.end()
                return
            }
            let updatedState = DropActivityAttributes.ContentState(
                secondsRemaining: remaining,
                receivedFrom: nil,
                receivedAmount: nil,
                isPaused: false
            )
            Task { await activity.update(using: updatedState) }
        }
    }
}
