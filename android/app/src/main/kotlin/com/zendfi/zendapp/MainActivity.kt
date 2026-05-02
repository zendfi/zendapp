package com.zendfi.zendapp

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.zendfi.zendapp/deep_links"
    private var pendingLink: String? = null
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    result.success(pendingLink)
                    pendingLink = null
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
            methodChannel?.invokeMethod("onDeepLink", url)
        }
    }

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
