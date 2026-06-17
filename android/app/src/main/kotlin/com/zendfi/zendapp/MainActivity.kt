package com.zendfi.zendapp

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val DEEP_LINK_CHANNEL = "com.zendfi.zendapp/deep_links"
    private val DROP_ADVERTISER_CHANNEL = "com.zendfi.app/drop_advertiser"

    private var pendingLink: String? = null
    private var deepLinkMethodChannel: MethodChannel? = null

    // Pending advertiser start — deferred if activity is not fully resumed.
    // Cleared in onResume after being dispatched.
    private var pendingStartPayload: Map<String, Any>? = null

    // Track resumed state so we know when it's safe to start the FGS.
    private var isActivityResumed = false

    private val mainHandler = Handler(Looper.getMainLooper())

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
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        isActivityResumed = true
        // Dispatch any deferred FGS start now that the activity is visible and
        // Android considers us foreground-eligible.
        pendingStartPayload?.let { payload ->
            pendingStartPayload = null
            doStartDropAdvertiserService(payload)
        }
    }

    override fun onPause() {
        super.onPause()
        isActivityResumed = false
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val url = extractUrl(intent)
        if (url != null) {
            deepLinkMethodChannel?.invokeMethod("onDeepLink", url)
        }
    }

    // ── Drop advertiser helpers ──────────────────────────────────────────────

    /**
     * Starts the DropAdvertiserService as a foreground service.
     *
     * Android 14/15 (API 34/35+) enforce that startForeground() can only be called
     * while the app is in a "foreground-allowed" state — i.e., while the activity
     * is resumed and visible.  Flutter's MethodChannel callbacks arrive on the
     * platform thread while the activity may momentarily be in onPause (e.g. a
     * bottom sheet animation triggered onPause on older API levels) or the system
     * may not yet consider the activity fully visible.
     *
     * Strategy:
     *  1. Post to the main thread (ensures we're not on the binder thread).
     *  2. If the activity is currently resumed, start immediately.
     *  3. If not, store as pendingStartPayload — onResume() will dispatch it.
     *  4. Catch ForegroundServiceStartNotAllowedException (API 31+) and store as
     *     pending in case the activity transitions just as we post.
     */
    private fun startDropAdvertiserService(payload: Map<String, Any>) {
        mainHandler.post {
            if (isActivityResumed) {
                doStartDropAdvertiserService(payload)
            } else {
                // Activity not yet resumed — defer until onResume
                android.util.Log.w("DropAdvertiser", "Activity not resumed — deferring FGS start")
                pendingStartPayload = payload
            }
        }
    }

    private fun doStartDropAdvertiserService(payload: Map<String, Any>) {
        val intent = Intent(this, DropAdvertiserService::class.java).apply {
            action = DropAdvertiserService.ACTION_START
            payload.forEach { (k, v) ->
                when (v) {
                    is String -> putExtra(k, v)
                    is Int    -> putExtra(k, v)
                    is Long   -> putExtra(k, v)
                    is Double -> putExtra(k, v)
                    is Boolean -> putExtra(k, v)
                    else      -> putExtra(k, v.toString())
                }
            }
        }
        try {
            // Use startService() (not startForegroundService()).
            // The service itself calls startForeground() in onStartCommand(), which
            // is the correct pattern. startForegroundService() can throw
            // ForegroundServiceStartNotAllowedException on Android 12+ if called
            // from a background-ish state; startService() is unrestricted.
            startService(intent)
        } catch (e: Exception) {
            // ForegroundServiceStartNotAllowedException (API 31) or SecurityException —
            // store as pending and retry on next resume.
            android.util.Log.e("DropAdvertiser", "startService failed: ${e.message} — will retry on resume")
            pendingStartPayload = payload
        }
    }

    private fun stopDropAdvertiserService() {
        // Clear any deferred start so a stop doesn't get overridden.
        pendingStartPayload = null
        mainHandler.post {
            try {
                val intent = Intent(this, DropAdvertiserService::class.java).apply {
                    action = DropAdvertiserService.ACTION_STOP
                }
                stopService(intent)
            } catch (e: Exception) {
                android.util.Log.e("DropAdvertiser", "stopService failed: ${e.message}")
            }
        }
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
            action == Intent.ACTION_VIEW && data != null -> data.toString()
            action == Intent.ACTION_VIEW && data?.scheme == "zendapp" -> data.toString()
            else -> null
        }
    }
}
