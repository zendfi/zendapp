package com.zend.ziro_vision

import android.content.Context
import io.flutter.FlutterInjector
import org.json.JSONObject
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.sin
import kotlin.math.sqrt

/** SplitMix64 + Box-Muller, exactly as `stub_reference.dart`. */
class SplitMix64(seed: Long) {
    private var state = seed
    fun next(): Long {
        state += -0x61c8864680b583ebL // 0x9E3779B97F4A7C15
        var z = state
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L // 0xBF58476D1CE4E5B9
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L // 0x94D049BB133111EB
        return z xor (z ushr 31)
    }
    fun nextDouble(): Double = (next() ushr 11) * (1.0 / 9007199254740992.0)
}

class GaussianStream(seed: Long) {
    private val rng = SplitMix64(seed)
    private var spare: Double? = null
    fun next(): Double {
        spare?.let { spare = null; return it }
        val u1 = 1.0 - rng.nextDouble()
        val u2 = rng.nextDouble()
        val r = sqrt(-2.0 * ln(u1))
        val t = 2.0 * Math.PI * u2
        spare = r * sin(t)
        return r * cos(t)
    }
}

object Stub {
    const val PALM_SEED = 0x5A49524FL
    const val FACE_SEED = 0x46414345L
    private const val SIDE = 32
    private const val INPUT = SIDE * SIDE

    fun matrix(seed: Long, rows: Int): FloatArray {
        val g = GaussianStream(seed)
        return FloatArray(rows * INPUT) { g.next().toFloat() }
    }

    /** CLAHE'd 224×224 → 7×7 box mean → mean/std → M·z → L2. */
    fun embed(claheGray: ByteArray, m: FloatArray, dims: Int): FloatArray {
        val x = DoubleArray(INPUT)
        for (r in 0 until SIDE) for (c in 0 until SIDE) {
            var s = 0
            for (dy in 0 until 7) {
                val row = (r * 7 + dy) * ImageMath.ROI + c * 7
                for (dx in 0 until 7) s += claheGray[row + dx].toInt() and 0xFF
            }
            x[r * SIDE + c] = s / 49.0
        }
        var mean = 0.0; for (v in x) mean += v; mean /= INPUT
        var variance = 0.0; for (v in x) variance += (v - mean) * (v - mean); variance /= INPUT
        var std = sqrt(variance); if (std < 1e-6) std = 1.0
        val z = DoubleArray(INPUT) { (x[it] - mean) / std }
        val y = DoubleArray(dims); var n2 = 0.0
        for (i in 0 until dims) {
            var acc = 0.0; val base = i * INPUT
            for (j in 0 until INPUT) acc += m[base + j] * z[j]
            y[i] = acc; n2 += acc * acc
        }
        if (n2 == 0.0) return FloatArray(dims)
        val n = sqrt(n2)
        return FloatArray(dims) { (y[it] / n).toFloat() }
    }

    fun average(vs: List<FloatArray>): FloatArray {
        val dims = vs.first().size
        val acc = DoubleArray(dims)
        for (v in vs) for (i in 0 until dims) acc[i] += v[i].toDouble()
        var n2 = 0.0; for (a in acc) n2 += a * a
        if (n2 == 0.0) return FloatArray(dims)
        val n = sqrt(n2)
        return FloatArray(dims) { (acc[it] / n).toFloat() }
    }
}

/**
 * Palm (and face) embedder: a LiteRT model from the app's flutter assets when present,
 * otherwise the deterministic stub ("palm-0" / "face-0").
 */
class Embedder(private val ctx: Context, private val asset: String, private val seed: Long, private val dims: Int, private val stubVersion: String) {
    private var interpreter: Interpreter? = null
    private var stubMatrix: FloatArray? = null
    var version: String = stubVersion
        private set

    private fun assetPath(name: String): String =
        FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("packages/ziro_vision/assets/models/$name")

    fun load() {
        if (interpreter != null || stubMatrix != null) return
        try {
            val fd = ctx.assets.openFd(assetPath("$asset.tflite"))
            val buf: MappedByteBuffer = FileInputStream(fd.fileDescriptor).channel.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
            interpreter = Interpreter(buf, Interpreter.Options().setNumThreads(4))
            version = try {
                val json = ctx.assets.open(assetPath("$asset.json")).bufferedReader().readText()
                JSONObject(json).optString("model_version", stubVersion)
            } catch (_: Exception) { stubVersion }
        } catch (_: Exception) {
            stubMatrix = Stub.matrix(seed, dims)
            version = stubVersion
        }
    }

    /** [gray] is the raw (pre-CLAHE) 224×224 crop. */
    fun embed(gray: ByteArray): FloatArray {
        val eq = ImageMath.clahe(gray)
        val interp = interpreter
        if (interp != null) {
            val input = ByteBuffer.allocateDirect(4 * eq.size).order(ByteOrder.nativeOrder())
            for (b in eq) input.putFloat((b.toInt() and 0xFF) / 255f)
            input.rewind()
            val out = Array(1) { FloatArray(dims) }
            interp.run(input, out)
            val v = out[0]
            var n = 0.0; for (f in v) n += f * f
            val s = sqrt(n).toFloat().takeIf { it > 0f } ?: 1f
            return FloatArray(dims) { v[it] / s }
        }
        return Stub.embed(eq, stubMatrix!!, dims)
    }

    fun close() { interpreter?.close(); interpreter = null }
}
