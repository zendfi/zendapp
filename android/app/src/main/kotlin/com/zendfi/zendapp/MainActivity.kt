package com.zendfi.zendapp

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {

    private val DEEP_LINK_CHANNEL = "com.zendfi.zendapp/deep_links"
    private val DROP_ADVERTISER_CHANNEL = "com.zendfi.app/drop_advertiser"
    private val DROP_DIAG_CHANNEL = "com.zendfi.app/drop_diagnostics"

    private var pendingLink: String? = null
    private var deepLinkMethodChannel: MethodChannel? = null

    // Pending advertiser start — deferred if activity is not fully resumed.
    private var pendingStartPayload: Map<String, Any>? = null

    // Track resumed state so we know when it's safe to start the FGS.
    private var isActivityResumed = false

    private val mainHandler = Handler(Looper.getMainLooper())

    // Persistent crash log file — survives app crashes so we can read it on next launch
    private val logFile: File by lazy {
        File(filesDir, "drop_crash.log")
    }

    private fun appendLog(tag: String, msg: String) {
        try {
            val ts = SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(Date())
            val line = "[$ts][$tag] $msg\n"
            android.util.Log.d("ZendDrop/$tag", msg)
            logFile.appendText(line)
            // Keep log under 32KB — trim oldest half if too large
            if (logFile.length() > 32_768) {
                val lines = logFile.readLines()
                logFile.writeText(lines.drop(lines.size / 2).joinToString("\n") + "\n")
            }
        } catch (_: Exception) {}
    }

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

        // ── Drop diagnostics channel — read crash log from Flutter ───────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DROP_DIAG_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "readCrashLog" -> {
                    val content = try { logFile.readText() } catch (_: Exception) { "" }
                    result.success(content)
                }
                "clearCrashLog" -> {
                    try { logFile.writeText("") } catch (_: Exception) {}
                    result.success(null)
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
                    appendLog("ADV", "startAdvertising called from Flutter, isResumed=$isActivityResumed API=${Build.VERSION.SDK_INT}")
                    startDropAdvertiserService(payload)
                    result.success(null)
                }
                "stopAdvertising" -> {
                    appendLog("ADV", "stopAdvertising called from Flutter")
                    stopDropAdvertiserService()
                    result.success(null)
                }
                "isServiceRunning" -> {
                    result.success(DropAdvertiserService.isRunning)
                    appendLog("ADV", "isServiceRunning=${DropAdvertiserService.isRunning}")
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        appendLog("LIFECYCLE", "onCreate API=${Build.VERSION.SDK_INT}")
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        isActivityResumed = true
        appendLog("LIFECYCLE", "onResume — dispatching pending=${pendingStartPayload != null}")
        pendingStartPayload?.let { payload ->
            pendingStartPayload = null
            appendLog("ADV", "onResume: dispatching deferred startDropAdvertiserService")
            doStartDropAdvertiserService(payload)
        }
    }

    override fun onPause() {
        super.onPause()
        isActivityResumed = false
        appendLog("LIFECYCLE", "onPause")
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
                appendLog("ADV", "Activity not resumed — deferring FGS start until onResume")
                pendingStartPayload = payload
            }
        }
    }

    private fun doStartDropAdvertiserService(payload: Map<String, Any>) {
        val intent = Intent(this, DropAdvertiserService::class.java).apply {
            action = DropAdvertiserService.ACTION_START
            payload.forEach { (k, v) ->
                when (v) {
                    is String  -> putExtra(k, v)
                    is Int     -> putExtra(k, v)
                    is Long    -> putExtra(k, v)
                    is Double  -> putExtra(k, v)
                    is Boolean -> putExtra(k, v)
                    else       -> putExtra(k, v.toString())
                }
            }
        }
        appendLog("ADV", "doStart: calling startService() API=${Build.VERSION.SDK_INT} isResumed=$isActivityResumed")
        try {
            startService(intent)
            appendLog("ADV", "doStart: startService() succeeded")
        } catch (e: Exception) {
            appendLog("ADV", "doStart: startService() FAILED: ${e.javaClass.simpleName}: ${e.message} — deferring to next resume")
            pendingStartPayload = payload
        }
    }

    private fun stopDropAdvertiserService() {
        pendingStartPayload = null
        mainHandler.post {
            try {
                val intent = Intent(this, DropAdvertiserService::class.java).apply {
                    action = DropAdvertiserService.ACTION_STOP
                }
                stopService(intent)
                appendLog("ADV", "stopService() succeeded")
            } catch (e: Exception) {
                appendLog("ADV", "stopService() failed: ${e.message}")
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
