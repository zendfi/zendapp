package com.zendfi.zendapp

import android.content.Intent
import android.os.Bundle
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val DEEP_LINK_CHANNEL = "com.zendfi.zendapp/deep_links"
    private val DROP_ADVERTISER_CHANNEL = "com.zendfi.app/drop_advertiser"

    private var pendingLink: String? = null
    private var deepLinkMethodChannel: MethodChannel? = null

    // Reference to the running DropAdvertiserService, communicated via Intent.
    // The service itself is a separate component; we start/stop it via Context.startForegroundService.
    private var dropAdvertiserService: DropAdvertiserService? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Deep-link channel ────────────────────────────────────────────────
        deepLinkMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEEP_LINK_CHANNEL
        )
        deepLinkMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    result.success(pendingLink)
                    pendingLink = null
                }
                else -> result.notImplemented()
            }
        }

        // ── Drop advertiser channel ──────────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DROP_ADVERTISER_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertising" -> {
                    @Suppress("UNCHECKED_CAST")
                    val payload = call.arguments as? Map<String, Any>
                    if (payload == null) {
                        result.error("INVALID_ARGS", "startAdvertising requires a beacon payload map", null)
                        return@setMethodCallHandler
                    }
                    startDropAdvertiserService(payload)
                    result.success(null)
                }
                "stopAdvertising" -> {
                    stopDropAdvertiserService()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Capture the link that launched the app
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // App was already running — forward the link immediately
        val url = extractUrl(intent)
        if (url != null) {
            deepLinkMethodChannel?.invokeMethod("onDeepLink", url)
        }
    }

    // ── Drop advertiser helpers ──────────────────────────────────────────────

    /**
     * Starts the DropAdvertiserService as a foreground service and passes the beacon
     * payload so it can begin BLE advertising immediately.
     *
     * The payload map is forwarded to the service via Intent extras.  Key–value pairs
     * must be String-keyed with String or numeric values (serialisable as Intent extras).
     */
    private fun startDropAdvertiserService(payload: Map<String, Any>) {
        val intent = Intent(this, DropAdvertiserService::class.java).apply {
            action = DropAdvertiserService.ACTION_START
            // Pass individual fields so the service can unpack them without JSON parsing
            payload.forEach { (k, v) ->
                when (v) {
                    is String -> putExtra(k, v)
                    is Int -> putExtra(k, v)
                    is Long -> putExtra(k, v)
                    is Double -> putExtra(k, v)
                    is Boolean -> putExtra(k, v)
                    else -> putExtra(k, v.toString())
                }
            }
        }
        ContextCompat.startForegroundService(this, intent)
    }

    private fun stopDropAdvertiserService() {
        val intent = Intent(this, DropAdvertiserService::class.java).apply {
            action = DropAdvertiserService.ACTION_STOP
        }
        stopService(intent)
    }

    // ── Deep-link helpers ────────────────────────────────────────────────────

    private fun handleIntent(intent: Intent?) {
        val url = extractUrl(intent) ?: return
        pendingLink = url
    }

    private fun extractUrl(intent: Intent?): String? {
        if (intent == null) return null
        val action = intent.action
        val data = intent.data

        return when {
            // Android App Link (https://zdfi.me/u/@...)
            action == Intent.ACTION_VIEW && data != null -> data.toString()
            // Custom scheme (zendapp://pay?...)
            action == Intent.ACTION_VIEW && data?.scheme == "zendapp" -> data.toString()
            else -> null
        }
    }
}
