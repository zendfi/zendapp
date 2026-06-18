package com.zendfi.zendapp

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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

    private val BLE_PERM_REQUEST_CODE = 1001

    private var pendingLink: String? = null
    private var deepLinkMethodChannel: MethodChannel? = null

    // Payload waiting for BLE permission grant before we can startService().
    private var permissionPendingPayload: Map<String, Any>? = null
    // Pending advertiser start — deferred if activity is not fully resumed.
    private var pendingStartPayload: Map<String, Any>? = null

    // Track resumed state so we know when it's safe to start the FGS.
    private var isActivityResumed = false

    private val mainHandler = Handler(Looper.getMainLooper())

    private val logFile: File by lazy { File(filesDir, "drop_crash.log") }

    private fun appendLog(tag: String, msg: String) {
        try {
            val ts = SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(Date())
            android.util.Log.d("ZendDrop/$tag", msg)
            logFile.appendText("[$ts][$tag] $msg\n")
            if (logFile.length() > 32_768) {
                val lines = logFile.readLines()
                logFile.writeText(lines.drop(lines.size / 2).joinToString("\n") + "\n")
            }
        } catch (_: Exception) {}
    }

    // ── BLE runtime permissions ──────────────────────────────────────────────

    /**
     * Returns true if all required BLE permissions are already granted.
     * On API < 31, BLE advertise doesn't require runtime permissions.
     */
    private fun hasBlePermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val perms = listOf(
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
        )
        return perms.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * Requests BLE permissions. [payload] is stored and dispatched once the
     * user grants (or is shown we need it).
     */
    private fun requestBlePermissions(payload: Map<String, Any>) {
        appendLog("PERM", "Requesting BLE runtime permissions (API ${Build.VERSION.SDK_INT})")
        permissionPendingPayload = payload
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.BLUETOOTH_ADVERTISE,
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_SCAN,
                ),
                BLE_PERM_REQUEST_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != BLE_PERM_REQUEST_CODE) return

        val allGranted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        appendLog("PERM", "BLE permission result: allGranted=$allGranted")

        val payload = permissionPendingPayload ?: return
        permissionPendingPayload = null

        if (allGranted) {
            appendLog("PERM", "Permissions granted — proceeding with startAdvertising")
            startDropAdvertiserService(payload)
        } else {
            appendLog("PERM", "Permissions DENIED — cannot start BLE advertiser")
            // Notify Flutter so the UI can show the correct error
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, DROP_ADVERTISER_CHANNEL)
                    .invokeMethod("onPermissionDenied", null)
            }
        }
    }

    // ── Flutter engine setup ─────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        deepLinkMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEEP_LINK_CHANNEL
        )
        deepLinkMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> { result.success(pendingLink); pendingLink = null }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DROP_DIAG_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readCrashLog" -> result.success(try { logFile.readText() } catch (_: Exception) { "" })
                    "clearCrashLog" -> { try { logFile.writeText("") } catch (_: Exception) {}; result.success(null) }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DROP_ADVERTISER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAdvertising" -> {
                        @Suppress("UNCHECKED_CAST")
                        val payload = call.arguments as? Map<String, Any>
                        if (payload == null) {
                            result.error("INVALID_ARGS", "startAdvertising requires a beacon payload map", null)
                            return@setMethodCallHandler
                        }
                        appendLog("ADV", "startAdvertising called from Flutter isResumed=$isActivityResumed API=${Build.VERSION.SDK_INT}")

                        if (!hasBlePermissions()) {
                            appendLog("ADV", "BLE permissions not granted — requesting from user")
                            requestBlePermissions(payload)
                            // Return success to Flutter — the actual start will happen in
                            // onRequestPermissionsResult once the user grants.
                            result.success(null)
                        } else {
                            startDropAdvertiserService(payload)
                            result.success(null)
                        }
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
                    "checkBlePermissions" -> {
                        val granted = hasBlePermissions()
                        appendLog("ADV", "checkBlePermissions=$granted")
                        result.success(granted)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

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
        pendingStartPayload = null
        appendLog("LIFECYCLE", "onPause — cleared pendingStartPayload")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        extractUrl(intent)?.let { deepLinkMethodChannel?.invokeMethod("onDeepLink", it) }
    }

    // ── Drop advertiser helpers ──────────────────────────────────────────────

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
            appendLog("ADV", "doStart: FAILED ${e.javaClass.simpleName}: ${e.message}")
            pendingStartPayload = payload
        }
    }

    private fun stopDropAdvertiserService() {
        pendingStartPayload = null
        mainHandler.post {
            try {
                stopService(Intent(this, DropAdvertiserService::class.java).apply {
                    action = DropAdvertiserService.ACTION_STOP
                })
                appendLog("ADV", "stopService() succeeded")
            } catch (e: Exception) {
                appendLog("ADV", "stopService() failed: ${e.message}")
            }
        }
    }

    // ── Deep-link helpers ────────────────────────────────────────────────────

    private fun handleIntent(intent: Intent?) { extractUrl(intent)?.let { pendingLink = it } }

    private fun extractUrl(intent: Intent?): String? {
        if (intent == null) return null
        return when {
            intent.action == Intent.ACTION_VIEW && intent.data != null -> intent.data.toString()
            intent.action == Intent.ACTION_VIEW && intent.data?.scheme == "zendapp" -> intent.data.toString()
            else -> null
        }
    }
}
