package com.zend.ziro_vision

import android.util.Base64
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Channels `zend/ziro_vision` and `zend/ziro_vision/events` (contracts §6). */
class ZiroVisionPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var sink: EventChannel.EventSink? = null
    private var session: CaptureSession? = null
    private var keys: DeviceKeys? = null
    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private var owner: LifecycleOwner? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        binding = b
        methods = MethodChannel(b.binaryMessenger, "zend/ziro_vision").also { it.setMethodCallHandler(this) }
        events = EventChannel(b.binaryMessenger, "zend/ziro_vision/events").also { it.setStreamHandler(this) }
        keys = DeviceKeys(b.applicationContext)
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        session?.dispose(); session = null
        scope.cancel()
    }

    override fun onAttachedToActivity(b: ActivityPluginBinding) { owner = b.activity as? LifecycleOwner }
    override fun onDetachedFromActivityForConfigChanges() { owner = null }
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) { owner = b.activity as? LifecycleOwner }
    override fun onDetachedFromActivity() { owner = null; session?.stop() }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    private fun session(): CaptureSession {
        session?.let { return it }
        val b = binding ?: throw IllegalStateException("not attached")
        return CaptureSession(b.applicationContext, b.textureRegistry) { sink?.success(it) }.also { session = it }
    }

    private fun bytes(call: MethodCall, key: String): ByteArray =
        Base64.decode(call.argument<String>(key) ?: throw IllegalArgumentException("missing $key"), Base64.DEFAULT)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> scope.launch {
                try {
                    val r = withContext(Dispatchers.Default) { session().prepare() }
                    keys?.let { k -> launch { k.prepareIntegrity() } }
                    result.success(r)
                } catch (e: Exception) { result.error("model_failed", e.message, null) }
            }
            "openPreview" -> {
                val o = owner ?: return result.error("camera_failed", "no activity", null)
                session().openPreview(o) { r, err -> if (r != null) result.success(r) else result.error(err ?: "camera_failed", null, null) }
            }
            "closePreview" -> { session?.closePreview(); result.success(null) }
            "startCapture" -> {
                @Suppress("UNCHECKED_CAST")
                session().start((call.arguments as? Map<String, Any?>) ?: emptyMap())
                result.success(null)
            }
            "flashShown" -> { session?.flashShown(call.argument<Int>("index") ?: -1); result.success(null) }
            "stopCapture" -> { session?.stop(); result.success(null) }
            "deviceKeyCreate" -> scope.launch {
                try {
                    val alias = call.argument<String>("alias") ?: "ziro_device"
                    result.success(withContext(Dispatchers.IO) { keys!!.create(alias, bytes(call, "challenge")) })
                } catch (e: Exception) { result.error("key_failed", e.message, null) }
            }
            "deviceKeySign" -> scope.launch {
                try {
                    val alias = call.argument<String>("alias") ?: "ziro_device"
                    val sig = withContext(Dispatchers.IO) { keys!!.sign(alias, bytes(call, "data")) }
                    result.success(mapOf("signature" to Base64.encodeToString(sig, Base64.NO_WRAP)))
                } catch (e: Exception) { result.error("key_failed", e.message, null) }
            }
            "integrityToken" -> scope.launch {
                try {
                    result.success(mapOf("token" to keys!!.integrityToken(bytes(call, "request_hash"))))
                } catch (e: Exception) { result.error("integrity_failed", e.message, null) }
            }
            else -> result.notImplemented()
        }
    }
}
