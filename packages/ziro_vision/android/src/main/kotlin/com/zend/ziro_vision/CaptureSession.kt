package com.zend.ziro_vision

import android.content.Context
import android.graphics.Bitmap
import android.hardware.camera2.CaptureRequest
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Base64
import android.util.Size
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.Camera2CameraControl
import androidx.camera.camera2.interop.CaptureRequestOptions
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import io.flutter.FlutterInjector
import io.flutter.view.TextureRegistry
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * One camera session: preview texture, hand landmarks, quality gate, templates and the flash
 * clip. Everything runs on [worker]; events go out on the main thread. Full frames stay in this
 * class and are dropped after each analysis callback.
 */
class CaptureSession(
    private val ctx: Context,
    private val textures: TextureRegistry,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var surface: TextureRegistry.SurfaceProducer? = null
    private var hands: HandLandmarker? = null
    private var faces: FaceDetector? = null
    private val palm = Embedder(ctx, "palm_embedding", Stub.PALM_SEED, 256, "palm-0")
    private val face = Embedder(ctx, "face_embedding", Stub.FACE_SEED, 512, "face-0")
    private var faceAvailable = false

    // Capture state (worker thread only).
    private enum class Phase { IDLE, NEUTRAL, FLASH, DONE }
    private var phase = Phase.IDLE
    private var mode = "pay"
    private var wantHands = mutableListOf("left", "right")
    private var wantFace = false
    private var colours = 0
    private var colourMs = 120
    private var deadlineMs = 0L
    private val good = mutableListOf<Pair<Double, FloatArray>>()
    private val geometry = mutableListOf<DoubleArray>()
    private val palmsDone = mutableListOf<Map<String, String>>()
    private val neutralCrops = mutableListOf<String>()
    private val flashFrames = mutableListOf<Map<String, String>>()
    private val landmarkTrack = mutableListOf<Map<String, String>>()
    private val shown = mutableListOf<Map<String, Any>>()
    private var faceEmbeddings = mutableListOf<FloatArray>()
    private var flashStartUs = 0L
    private var lastGuide = ""
    private var lastQuad: List<ImageMath.P>? = null

    private fun assetPath(name: String) =
        FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("packages/ziro_vision/assets/models/$name")

    private fun post(m: Map<String, Any?>) = main.post { emit(m) }

    fun prepare(): Map<String, Any?> {
        if (hands == null) {
            val base = BaseOptions.builder().setModelAssetPath(assetPath("hand_landmarker.task"))
            hands = try {
                HandLandmarker.createFromOptions(ctx, HandLandmarker.HandLandmarkerOptions.builder()
                    .setBaseOptions(base.setDelegate(Delegate.GPU).build())
                    .setRunningMode(RunningMode.VIDEO).setNumHands(1).build())
            } catch (_: Exception) {
                HandLandmarker.createFromOptions(ctx, HandLandmarker.HandLandmarkerOptions.builder()
                    .setBaseOptions(BaseOptions.builder().setModelAssetPath(assetPath("hand_landmarker.task")).setDelegate(Delegate.CPU).build())
                    .setRunningMode(RunningMode.VIDEO).setNumHands(1).build())
            }
            faceAvailable = try {
                faces = FaceDetector.createFromOptions(ctx, FaceDetector.FaceDetectorOptions.builder()
                    .setBaseOptions(BaseOptions.builder().setModelAssetPath(assetPath("blaze_face_short_range.tflite")).build())
                    .setRunningMode(RunningMode.VIDEO).build())
                true
            } catch (_: Exception) { false }
        }
        palm.load()
        if (faceAvailable) face.load()
        // Warm the embedder on a blank crop so the first real frame is fast.
        palm.embed(ByteArray(ImageMath.ROI * ImageMath.ROI))
        return mapOf("model_version" to palm.version, "face_model_version" to if (faceAvailable) face.version else null)
    }

    fun openPreview(owner: LifecycleOwner, reply: (Map<String, Any?>?, String?) -> Unit) {
        val future = ProcessCameraProvider.getInstance(ctx)
        future.addListener({
            try {
                val p = future.get()
                provider = p
                val sp = surface ?: textures.createSurfaceProducer().also { surface = it }
                val res = ResolutionSelector.Builder().setResolutionStrategy(
                    ResolutionStrategy(Size(1280, 720), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)).build()
                val preview = Preview.Builder().setResolutionSelector(res).build()
                preview.setSurfaceProvider { req ->
                    sp.setSize(req.resolution.width, req.resolution.height)
                    req.provideSurface(sp.surface, ContextCompat.getMainExecutor(ctx)) {}
                }
                val analysisRes = ResolutionSelector.Builder().setResolutionStrategy(
                    ResolutionStrategy(Size(640, 480), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)).build()
                val ab = ImageAnalysis.Builder().setResolutionSelector(analysisRes)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                Camera2Interop.Extender(ab).setCaptureRequestOption(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, android.util.Range(30, 30))
                val analysis = ab.build()
                analysis.setAnalyzer(worker) { img -> analyze(img) }
                p.unbindAll()
                val cam = p.bindToLifecycle(owner, CameraSelector.DEFAULT_FRONT_CAMERA, preview, analysis)
                camera = cam
                val turns = (cam.cameraInfo.sensorRotationDegrees / 90) % 4
                reply(mapOf("texture_id" to sp.id(), "width" to 1280, "height" to 720, "quarter_turns" to turns, "mirror" to true), null)
            } catch (e: SecurityException) {
                reply(null, "camera_denied")
            } catch (e: Exception) {
                reply(null, "camera_failed")
            }
        }, ContextCompat.getMainExecutor(ctx))
    }

    fun closePreview() {
        if (phase == Phase.NEUTRAL || phase == Phase.FLASH) return
        provider?.unbindAll()
        camera = null
    }

    fun start(args: Map<String, Any?>) = worker.execute {
        mode = args["mode"] as? String ?: "pay"
        @Suppress("UNCHECKED_CAST")
        wantHands = ((args["hands"] as? List<String>) ?: listOf("left", "right")).toMutableList()
        wantFace = (args["face"] as? Boolean ?: false) && faceAvailable
        @Suppress("UNCHECKED_CAST")
        colours = (args["colours"] as? List<String>)?.size ?: 0
        colourMs = (args["colour_ms"] as? Number)?.toInt() ?: 120
        deadlineMs = SystemClock.elapsedRealtime() + ((args["timeout_ms"] as? Number)?.toLong() ?: 30_000L)
        resetBuffers()
        palmsDone.clear()
        lockExposure(false)
        phase = Phase.NEUTRAL
    }

    fun flashShown(index: Int) {
        val t = SystemClock.elapsedRealtimeNanos() / 1000
        worker.execute {
            if (index == -1 && flashStartUs == 0L) flashStartUs = t
            shown.add(mapOf("index" to index, "t_us" to t.toString()))
        }
    }

    fun stop() = worker.execute {
        phase = Phase.IDLE
        resetBuffers()
        lockExposure(false)
    }

    fun dispose() {
        stop()
        main.post { provider?.unbindAll(); surface?.release(); surface = null }
        worker.execute { hands?.close(); faces?.close(); palm.close(); face.close() }
        worker.shutdown()
    }

    private fun resetBuffers() {
        good.clear(); geometry.clear(); neutralCrops.clear(); flashFrames.clear(); landmarkTrack.clear(); shown.clear()
        faceEmbeddings.clear(); flashStartUs = 0L; lastGuide = ""; lastQuad = null
    }

    private fun lockExposure(lock: Boolean) {
        val cam = camera ?: return
        val opts = CaptureRequestOptions.Builder()
            .setCaptureRequestOption(CaptureRequest.CONTROL_AE_LOCK, lock)
            .setCaptureRequestOption(CaptureRequest.CONTROL_AWB_LOCK, lock)
            .build()
        Camera2CameraControl.from(cam.cameraControl).setCaptureRequestOptions(opts)
    }

    private fun guide(code: String) {
        if (code != lastGuide) { lastGuide = code; post(mapOf("type" to "guide", "code" to code)) }
    }

    /** Frame time in the elapsedRealtime domain (µs), whatever clock the sensor uses. */
    private fun frameUs(img: ImageProxy): Long {
        val ts = img.imageInfo.timestamp
        val rt = SystemClock.elapsedRealtimeNanos()
        val up = SystemClock.uptimeMillis() * 1_000_000L
        val t = if (abs(ts - rt) <= abs(ts - up)) ts else ts + (rt - up)
        return t / 1000
    }

    /** Upright, mirrored RGB copy of the frame. */
    private fun upright(img: ImageProxy): Triple<ByteArray, Int, Int> {
        val plane = img.planes[0]
        val buf = plane.buffer
        val w = img.width; val h = img.height
        val stride = plane.rowStride
        val rot = img.imageInfo.rotationDegrees
        val (ow, oh) = if (rot == 90 || rot == 270) h to w else w to h
        val out = ByteArray(ow * oh * 3)
        val row = ByteArray(stride)
        for (y in 0 until h) {
            buf.position(y * stride)
            buf.get(row, 0, min(stride, buf.remaining()))
            for (x in 0 until w) {
                val (ux, uy) = when (rot) {
                    90 -> (h - 1 - y) to x
                    180 -> (w - 1 - x) to (h - 1 - y)
                    270 -> y to (w - 1 - x)
                    else -> x to y
                }
                val mx = ow - 1 - ux // mirror: selfie view, as MediaPipe handedness expects
                val o = (uy * ow + mx) * 3
                out[o] = row[x * 4]; out[o + 1] = row[x * 4 + 1]; out[o + 2] = row[x * 4 + 2]
            }
        }
        return Triple(out, ow, oh)
    }

    private fun toBitmap(rgb: ByteArray, w: Int, h: Int): Bitmap {
        val px = IntArray(w * h) { i ->
            (0xFF shl 24) or ((rgb[i * 3].toInt() and 0xFF) shl 16) or ((rgb[i * 3 + 1].toInt() and 0xFF) shl 8) or (rgb[i * 3 + 2].toInt() and 0xFF)
        }
        return Bitmap.createBitmap(px, w, h, Bitmap.Config.ARGB_8888)
    }

    private fun analyze(img: ImageProxy) {
        try {
            if (phase == Phase.IDLE || phase == Phase.DONE) return
            if (SystemClock.elapsedRealtime() > deadlineMs) {
                phase = Phase.IDLE
                lockExposure(false)
                post(mapOf("type" to "error", "code" to "timeout"))
                return
            }
            val tUs = frameUs(img)
            val (rgb, w, h) = upright(img)
            val mp = BitmapImageBuilder(toBitmap(rgb, w, h)).build()
            val res = hands?.detectForVideo(mp, tUs / 1000) ?: return
            if (res.landmarks().isEmpty()) {
                if (phase == Phase.NEUTRAL) guide("show_palm")
                if (phase == Phase.FLASH) flashFrame(tUs, rgb, w, h, null)
                return
            }
            val lm = res.landmarks()[0]
            val pts = lm.map { ImageMath.P(it.x() * w.toDouble(), it.y() * h.toDouble()) }
            val handed = res.handedness().firstOrNull()?.firstOrNull()?.categoryName()?.lowercase() ?: ""
            val track = FloatArray(63).also { a -> lm.forEachIndexed { i, p -> a[i * 3] = p.x(); a[i * 3 + 1] = p.y(); a[i * 3 + 2] = p.z() } }
            when (phase) {
                Phase.NEUTRAL -> neutral(tUs, rgb, w, h, pts, handed, mp)
                Phase.FLASH -> flashFrame(tUs, rgb, w, h, pts, track)
                else -> {}
            }
        } catch (e: Exception) {
            post(mapOf("type" to "error", "code" to "model_failed"))
        } finally {
            img.close()
        }
    }

    private fun gray(rgb: ByteArray, w: Int, h: Int) = ByteArray(w * h) { i ->
        ImageMath.luma(rgb[i * 3].toInt() and 0xFF, rgb[i * 3 + 1].toInt() and 0xFF, rgb[i * 3 + 2].toInt() and 0xFF).toByte()
    }

    private fun neutral(tUs: Long, rgb: ByteArray, w: Int, h: Int, pts: List<ImageMath.P>, handed: String, mp: com.google.mediapipe.framework.image.MPImage) {
        val target = wantHands.firstOrNull() ?: return
        if (mode == "enroll" && handed.isNotEmpty() && handed != target) { guide("other_hand"); return }
        val widthPx = kotlin.math.hypot(pts[5].x - pts[17].x, pts[5].y - pts[17].y)
        if (widthPx < 0.12 * min(w, h)) { guide("move_closer"); return }
        if (widthPx > 0.45 * min(w, h)) { guide("move_back"); return }
        // Palm facing the camera: the wrist→index×wrist→pinky normal flips with the back of the hand.
        val cross = (pts[5].x - pts[0].x) * (pts[17].y - pts[0].y) - (pts[5].y - pts[0].y) * (pts[17].x - pts[0].x)
        val facing = if (handed == "left") cross < 0 else cross > 0
        if (handed.isNotEmpty() && !facing) { guide("show_palm"); return }
        val quad = ImageMath.palmQuad(pts)
        val g = gray(rgb, w, h)
        val crop = ImageMath.warpGray(g, w, h, quad, ImageMath.ROI) ?: return
        val level = ImageMath.mean(crop)
        if (level < 40) { guide("too_dark"); return }
        if (ImageMath.saturatedFraction(crop) > 0.08) { guide("too_bright"); return }
        val sharp = ImageMath.laplacianVariance(crop, ImageMath.ROI, ImageMath.ROI)
        if (sharp < 25.0) { guide("hold_still"); return }
        guide("ok")
        lastQuad = quad
        good.add(sharp to palm.embed(crop))
        geometry.add(ImageMath.handGeometry(pts))
        if (wantFace && faceEmbeddings.size < 4) captureFace(rgb, w, h, mp, tUs)
        if (mode == "pay" && neutralCrops.size < 2) {
            ImageMath.warpRgb(rgb, w, h, quad, ImageMath.FLASH)?.let { neutralCrops.add(b64(it)) }
        }
        if (good.size < 8) return
        val best = good.sortedByDescending { it.first }.take(8).map { it.second }
        palmsDone.add(mapOf("hand" to (if (handed.isNotEmpty()) handed else target), "embedding" to b64(F16.encode(Stub.average(best)))))
        good.clear()
        wantHands.removeAt(0)
        if (mode == "enroll") {
            post(mapOf("type" to "hand_done", "hand" to target))
            if (wantHands.isEmpty()) finish(null) else lastGuide = ""
            return
        }
        // Pay: one hand is enough. Hold exposure steady for the flash, then let Dart paint.
        lockExposure(true)
        phase = Phase.FLASH
        post(mapOf("type" to "ready_for_flash"))
    }

    private fun captureFace(rgb: ByteArray, w: Int, h: Int, mp: com.google.mediapipe.framework.image.MPImage, tUs: Long) {
        val det = faces?.detectForVideo(mp, tUs / 1000)?.detections()?.firstOrNull() ?: return
        val b = det.boundingBox()
        val s = max(b.width(), b.height()).toDouble() * 1.2
        val cx = b.centerX().toDouble(); val cy = b.centerY().toDouble()
        val quad = listOf(
            ImageMath.P(cx - s / 2, cy - s / 2), ImageMath.P(cx + s / 2, cy - s / 2),
            ImageMath.P(cx + s / 2, cy + s / 2), ImageMath.P(cx - s / 2, cy + s / 2),
        )
        val crop = ImageMath.warpGray(gray(rgb, w, h), w, h, quad, ImageMath.ROI) ?: return
        faceEmbeddings.add(face.embed(crop))
    }

    private fun flashFrame(tUs: Long, rgb: ByteArray, w: Int, h: Int, pts: List<ImageMath.P>?, track: FloatArray? = null) {
        val quad = pts?.let { ImageMath.palmQuad(it) }?.also { lastQuad = it } ?: lastQuad ?: return
        if (flashStartUs != 0L && tUs >= flashStartUs) {
            ImageMath.warpRgb(rgb, w, h, quad, ImageMath.FLASH)?.let { flashFrames.add(mapOf("t_us" to tUs.toString(), "rgb" to b64(it))) }
            if (track != null) landmarkTrack.add(mapOf("t_us" to tUs.toString(), "points" to b64(F16.encode(track))))
        }
        val endUs = flashStartUs + (colours + 1) * colourMs * 1000L + 250_000L
        if (flashStartUs != 0L && (tUs > endUs || flashFrames.size >= 30)) finish(mapOf(
            "neutral" to neutralCrops.toList(),
            "frames" to flashFrames.toList(),
            "shown" to shown.toList(),
            "landmarks" to landmarkTrack.toList(),
        ))
    }

    private fun finish(flash: Map<String, Any?>?) {
        phase = Phase.DONE
        lockExposure(false)
        val geo = DoubleArray(24)
        for (g in geometry) for (i in 0 until 24) geo[i] += g[i] / geometry.size
        val faceVec = if (faceEmbeddings.isNotEmpty()) b64(F16.encode(Stub.average(faceEmbeddings))) else null
        val version = palm.version + (if (faceVec != null) "+${face.version}" else "")
        val ev = mutableMapOf<String, Any?>(
            "type" to "captured", "model_version" to version, "palms" to palmsDone.toList(),
            "geometry" to b64(F16.encode(FloatArray(24) { geo[it].toFloat() })), "face" to faceVec,
        )
        if (flash != null) ev["flash"] = flash
        post(ev)
        resetBuffers()
    }

    private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)
}

/** IEEE-754 half floats, little-endian (contracts §0). */
object F16 {
    fun encode(v: FloatArray): ByteArray {
        val out = ByteArray(v.size * 2)
        for (i in v.indices) {
            val h = android.util.Half.toHalf(v[i]).toInt()
            out[i * 2] = (h and 0xFF).toByte(); out[i * 2 + 1] = ((h shr 8) and 0xFF).toByte()
        }
        return out
    }
}
