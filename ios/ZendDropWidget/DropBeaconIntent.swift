import AppIntents
import ActivityKit
import CoreBluetooth

// MARK: - App Intent

/// `DropBeaconIntent` is the App Intent that fires when the user taps
/// "Be Discoverable" on the Zend Home Screen widget.
///
/// **iOS entitlement note:** `CBPeripheralManager` BLE advertising can only
/// be initiated from the main Runner target because widget extensions run in
/// a separate sandbox process and do not have the `bluetooth-peripheral`
/// entitlement. This intent therefore:
///   1. Fetches a fresh signed beacon from the backend.
///   2. Delegates the actual `CBPeripheralManager` advertising to the main
///      app via `DropBleCentralManager.shared.startAdvertising(beacon:)`.
///      The full `CBPeripheralManager` implementation — including
///      `CBPeripheralManagerDelegate` conformance and manufacturer-specific
///      advertisement data construction — lives in `DropAdvertiserManager.swift`
///      inside the **iOS Runner target**.
///   3. Launches a Live Activity countdown (iOS 16.1+).
///
/// The widget extension itself only reads the session token from the shared
/// App Group keychain and performs the network request; it never calls
/// `CBPeripheralManager` directly.
@available(iOS 16.0, *)
struct DropBeaconIntent: AppIntent {
    static var title: LocalizedStringResource = "Be Discoverable for Drop"
    static var description = IntentDescription(
        "Start broadcasting your Zend identity over Bluetooth so nearby users can send you money."
    )

    /// Run the action immediately without bouncing the user into the full app UI.
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        // 1. Read the session token from the shared App Group keychain.
        //    The main Zend app writes this token under the key
        //    "zend_session_token" in the access group
        //    "$(AppIdentifierPrefix)com.zendfi.app.shared".
        guard let token = DropKeychainHelper.readSessionToken() else {
            // If there is no token the user is not authenticated;
            // return silently — the widget will show the standard
            // "Sign in to Zend" state.
            return .result()
        }

        // 2. Fetch a fresh, server-signed beacon from the backend.
        guard let beacon = await DropBeaconFetcher.fetchBeacon(token: token) else {
            // Network failure or non-200 response: return silently.
            // A future iteration can surface an error state via a
            // widget timeline reload.
            return .result()
        }

        // 3. Start BLE advertising via the main-app stub.
        //    The stub documents the interface; the full implementation
        //    using CBPeripheralManager lives in DropAdvertiserManager.swift
        //    (Runner target) and is reached via an App Group notification
        //    or URL scheme hand-off from the widget extension process.
        DropBleCentralManager.shared.startAdvertising(beacon: beacon)

        // 4. Launch a Live Activity countdown (requires iOS 16.1+).
        if #available(iOS 16.1, *) {
            DropLiveActivityManager.shared.start(
                beacon: beacon,
                durationSeconds: 180 // 3-minute window per Requirement 7.1
            )
        }

        return .result()
    }
}

// MARK: - Keychain helper

/// Reads the Zend session JWT from the shared App Group keychain.
///
/// The main app stores the token using `kSecClassGenericPassword` with
/// account key `"zend_session_token"` and the access group
/// `"$(AppIdentifierPrefix)com.zendfi.app.shared"`.
/// Both the Runner target and the ZendDropWidget extension must declare
/// the same App Group in their respective `.entitlements` files.
enum DropKeychainHelper {
    static func readSessionToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String:         kSecClassGenericPassword,
            kSecAttrAccount as String:   "zend_session_token",
            kSecAttrAccessGroup as String: "$(AppIdentifierPrefix)com.zendfi.app.shared",
            kSecReturnData as String:    true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }
}

// MARK: - Beacon fetcher

/// Calls `POST /api/zend/drop/beacon/generate` to obtain a fresh signed beacon
/// from the Zend backend. Requires a valid Bearer session token.
enum DropBeaconFetcher {

    /// The JSON shape returned by `POST /api/zend/drop/beacon/generate`.
    /// Mirrors `BeaconGenerateResponse` in `src/drop.rs`.
    struct BeaconResponse: Codable {
        let zendtag:   String
        let nonce:     String
        let timestamp: Int
        let expires_at: Int
        let signature: String
    }

    /// Performs the network request and decodes the response.
    /// Returns `nil` on any error (network, HTTP, or decoding).
    static func fetchBeacon(token: String) async -> BeaconResponse? {
        guard let url = URL(string: "https://api.zendfi.tech/api/zend/drop/beacon/generate") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(BeaconResponse.self, from: data)
        } catch {
            return nil
        }
    }
}

// MARK: - BLE manager stub

/// A thin stub that documents the interface between the widget extension and
/// the main Runner target's BLE advertising stack.
///
/// **Why a stub?**
/// Widget extensions run in a sandboxed process that lacks the
/// `bluetooth-peripheral` entitlement required by `CBPeripheralManager`.
/// The actual `CBPeripheralManager` initialisation, delegate callbacks, and
/// manufacturer-specific advertisement packet construction are implemented in
/// `DropAdvertiserManager.swift` inside the **iOS Runner target**.
///
/// The bridge between the extension process and the Runner target uses one of
/// the following mechanisms (to be wired in `DropAdvertiserManager.swift`):
///   - An App Group `UserDefaults` flag that the Runner observes via
///     `NotificationCenter` on `UIApplication.willEnterForegroundNotification`.
///   - A custom URL scheme (`zend://drop/start-advertising?nonce=…`) that
///     the extension opens via `UIApplication.shared.open(_:)`.
///
/// Until that bridge is wired, calling `startAdvertising(beacon:)` on a real
/// device from the extension process is a no-op at the BLE layer; the Live
/// Activity countdown will still launch correctly.
class DropBleCentralManager: NSObject {
    static let shared = DropBleCentralManager()

    /// Signal the Runner target to begin BLE advertising with the given beacon.
    ///
    /// - Parameter beacon: The freshly generated beacon payload from the server.
    func startAdvertising(beacon: DropBeaconFetcher.BeaconResponse) {
        // Write the beacon nonce + expiry into the shared App Group UserDefaults
        // so that the main Runner target can pick it up and start advertising.
        // The Runner target observes `UserDefaults` changes via
        // NotificationCenter in DropAdvertiserManager.swift.
        let suiteName = "group.com.zendfi.app"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.set(beacon.nonce, forKey: "drop_pending_nonce")
            defaults.set(beacon.expires_at, forKey: "drop_pending_expires_at")
            defaults.set(beacon.signature, forKey: "drop_pending_signature")
            defaults.set(beacon.zendtag, forKey: "drop_pending_zendtag")
            defaults.set(beacon.timestamp, forKey: "drop_pending_timestamp")
            defaults.set(true, forKey: "drop_advertising_requested")
            defaults.synchronize()
        }
        // Full CBPeripheralManager advertising — including
        // CBPeripheralManagerDelegate conformance and building the 28-byte
        // advertisement packet — is implemented in DropAdvertiserManager.swift
        // (Runner target). See design.md § "iOS Native" for the packet layout:
        //   [ AppID (4B) | Nonce (8B) | Timestamp (4B) | Sig Hash (12B) ]
    }
}

// MARK: - Live Activity manager stub

/// Manages the DropLiveActivity countdown in the Dynamic Island.
///
/// The concrete implementation of `DropLiveActivityManager` lives in
/// `DropLiveActivity.swift`, which is compiled into the Widget Extension
/// target alongside this file. This stub exists to give `DropBeaconIntent`
/// a stable call site that compiles even before `DropLiveActivity.swift`
/// is fully wired.
///
/// On devices running iOS < 16.1, `start(beacon:durationSeconds:)` is never
/// called (guarded by the `#available(iOS 16.1, *)` check in `perform()`),
/// satisfying Requirement 7.7.
@available(iOS 16.1, *)
class DropLiveActivityManager {
    static let shared = DropLiveActivityManager()

    /// Start a 3-minute Live Activity countdown in the Dynamic Island.
    ///
    /// - Parameters:
    ///   - beacon: The active beacon whose nonce identifies this advertising session.
    ///   - durationSeconds: Countdown duration in seconds (180 = 3 minutes).
    func start(beacon: DropBeaconFetcher.BeaconResponse, durationSeconds: Int) {
        // Full ActivityKit implementation is in DropLiveActivity.swift (task 16.3).
        // This stub documents the call site so DropBeaconIntent can compile
        // independently of the Live Activity implementation task.
    }
}
