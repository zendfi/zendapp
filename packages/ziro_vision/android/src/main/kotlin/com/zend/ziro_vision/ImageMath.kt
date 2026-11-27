package com.zend.ziro_vision

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * On-device image math. Follows `lib/src/stub_reference.dart` step by step so the same crop
 * gives the same vector on Android, iOS and in the Dart reference.
 */
object ImageMath {
    const val ROI = 224
    const val FLASH = 96
    private const val TILES = 8
    private const val TILE = ROI / TILES // 28
    private const val TILE_PIXELS = TILE * TILE // 784
    private const val CLIP = 6

    /** Integer BT.601 luma: (77 R + 150 G + 29 B) >> 8. */
    fun luma(r: Int, g: Int, b: Int): Int = (77 * r + 150 * g + 29 * b) shr 8

    data class P(val x: Double, val y: Double)

    /** TL = P5, TR = P17, BR = P0 + 0.8 (P17 − P9), BL = P0 + 0.8 (P5 − P9). */
    fun palmQuad(p: List<P>): List<P> {
        val p0 = p[0]; val p5 = p[5]; val p9 = p[9]; val p17 = p[17]
        return listOf(
            p5, p17,
            P(p0.x + 0.8 * (p17.x - p9.x), p0.y + 0.8 * (p17.y - p9.y)),
            P(p0.x + 0.8 * (p5.x - p9.x), p0.y + 0.8 * (p5.y - p9.y)),
        )
    }

    /** Homography from the destination square to [quad]; h0..h7 (h8 = 1), or null. */
    fun homographyToQuad(quad: List<P>, size: Int): DoubleArray? {
        val s = (size - 1).toDouble()
        val dst = listOf(P(0.0, 0.0), P(s, 0.0), P(s, s), P(0.0, s))
        val a = Array(8) { DoubleArray(9) }
        for (k in 0 until 4) {
            val u = dst[k].x; val v = dst[k].y; val x = quad[k].x; val y = quad[k].y
            doubleArrayOf(u, v, 1.0, 0.0, 0.0, 0.0, -u * x, -v * x, x).copyInto(a[2 * k])
            doubleArrayOf(0.0, 0.0, 0.0, u, v, 1.0, -u * y, -v * y, y).copyInto(a[2 * k + 1])
        }
        for (col in 0 until 8) {
            var piv = col
            for (r in col + 1 until 8) if (abs(a[r][col]) > abs(a[piv][col])) piv = r
            if (abs(a[piv][col]) < 1e-12) return null
            val tmp = a[col]; a[col] = a[piv]; a[piv] = tmp
            for (r in 0 until 8) {
                if (r == col) continue
                val f = a[r][col] / a[col][col]
                if (f == 0.0) continue
                for (c in col until 9) a[r][c] -= f * a[col][c]
            }
        }
        return DoubleArray(8) { a[it][8] / a[it][it] }
    }

    private fun clampI(v: Int, lo: Int, hi: Int) = if (v < lo) lo else if (v > hi) hi else v

    fun sampleBilinear(img: ByteArray, w: Int, h: Int, x: Double, y: Double): Int {
        val x0 = floor(x).toInt(); val y0 = floor(y).toInt()
        val fx = x - x0; val fy = y - y0
        fun px(xx: Int, yy: Int) = img[clampI(yy, 0, h - 1) * w + clampI(xx, 0, w - 1)].toInt() and 0xFF
        val v = (1 - fy) * ((1 - fx) * px(x0, y0) + fx * px(x0 + 1, y0)) +
            fy * ((1 - fx) * px(x0, y0 + 1) + fx * px(x0 + 1, y0 + 1))
        return clampI(floor(v + 0.5).toInt(), 0, 255)
    }

    fun warpGray(img: ByteArray, w: Int, h: Int, quad: List<P>, size: Int): ByteArray? {
        val hm = homographyToQuad(quad, size) ?: return null
        val out = ByteArray(size * size)
        for (v in 0 until size) for (u in 0 until size) {
            val den = hm[6] * u + hm[7] * v + 1.0
            val x = (hm[0] * u + hm[1] * v + hm[2]) / den
            val y = (hm[3] * u + hm[4] * v + hm[5]) / den
            out[v * size + u] = sampleBilinear(img, w, h, x, y).toByte()
        }
        return out
    }

    /** Same warp per RGB channel (interleaved), for the 96×96 flash crops. */
    fun warpRgb(rgb: ByteArray, w: Int, h: Int, quad: List<P>, size: Int): ByteArray? {
        val hm = homographyToQuad(quad, size) ?: return null
        val out = ByteArray(size * size * 3)
        val ch = Array(3) { c -> ByteArray(w * h) { i -> rgb[i * 3 + c] } }
        for (v in 0 until size) for (u in 0 until size) {
            val den = hm[6] * u + hm[7] * v + 1.0
            val x = (hm[0] * u + hm[1] * v + hm[2]) / den
            val y = (hm[3] * u + hm[4] * v + hm[5]) / den
            for (c in 0 until 3) out[(v * size + u) * 3 + c] = sampleBilinear(ch[c], w, h, x, y).toByte()
        }
        return out
    }

    private data class T(val i0: Int, val i1: Int, val a: Double)

    private fun tileIndex(f: Double): T {
        val i = floor(f).toInt()
        if (i < 0) return T(0, 0, 0.0)
        if (i >= TILES - 1) return T(TILES - 1, TILES - 1, 0.0)
        return T(i, i + 1, f - i)
    }

    fun clahe(gray: ByteArray): ByteArray {
        val luts = Array(TILES * TILES) { IntArray(256) }
        val hist = IntArray(256)
        for (ty in 0 until TILES) for (tx in 0 until TILES) {
            hist.fill(0)
            for (y in ty * TILE until (ty + 1) * TILE) for (x in tx * TILE until (tx + 1) * TILE) {
                hist[gray[y * ROI + x].toInt() and 0xFF]++
            }
            var excess = 0
            for (b in 0 until 256) if (hist[b] > CLIP) { excess += hist[b] - CLIP; hist[b] = CLIP }
            val inc = excess / 256; val rem = excess % 256
            for (b in 0 until 256) hist[b] += inc + (if (b < rem) 1 else 0)
            val lut = luts[ty * TILES + tx]
            var cdf = 0
            for (b in 0 until 256) { cdf += hist[b]; lut[b] = min(255, (cdf * 255) / TILE_PIXELS) }
        }
        val out = ByteArray(gray.size)
        for (y in 0 until ROI) {
            val ty = tileIndex((y + 0.5) / TILE - 0.5)
            for (x in 0 until ROI) {
                val tx = tileIndex((x + 0.5) / TILE - 0.5)
                val p = gray[y * ROI + x].toInt() and 0xFF
                val l00 = luts[ty.i0 * TILES + tx.i0][p]; val l01 = luts[ty.i0 * TILES + tx.i1][p]
                val l10 = luts[ty.i1 * TILES + tx.i0][p]; val l11 = luts[ty.i1 * TILES + tx.i1][p]
                val v = (1 - ty.a) * ((1 - tx.a) * l00 + tx.a * l01) + ty.a * ((1 - tx.a) * l10 + tx.a * l11)
                out[y * ROI + x] = clampI(floor(v + 0.5).toInt(), 0, 255).toByte()
            }
        }
        return out
    }

    private val PAIRS = intArrayOf(
        1, 2, 2, 3, 3, 4, 5, 6, 6, 7, 7, 8, 9, 10, 10, 11, 11, 12, 13, 14, 14, 15, 15, 16, 17, 18, 18, 19, 19, 20,
        0, 1, 0, 5, 0, 9, 0, 13, 0, 17, 5, 9, 9, 13, 13, 17, 2, 5,
    )

    /** 24 distances over palm width |P5 − P17| (README "Hand geometry"). */
    fun handGeometry(p: List<P>): DoubleArray {
        fun d(a: Int, b: Int): Double { val dx = p[a].x - p[b].x; val dy = p[a].y - p[b].y; return sqrt(dx * dx + dy * dy) }
        val w = d(5, 17)
        val out = DoubleArray(24)
        if (w <= 0) return out
        for (i in 0 until 24) out[i] = d(PAIRS[2 * i], PAIRS[2 * i + 1]) / w
        return out
    }

    /** Variance of the 4-neighbour Laplacian over a grayscale crop. */
    fun laplacianVariance(g: ByteArray, w: Int, h: Int): Double {
        var sum = 0.0; var sum2 = 0.0; var n = 0
        for (y in 1 until h - 1) for (x in 1 until w - 1) {
            val c = g[y * w + x].toInt() and 0xFF
            val l = (g[y * w + x - 1].toInt() and 0xFF) + (g[y * w + x + 1].toInt() and 0xFF) +
                (g[(y - 1) * w + x].toInt() and 0xFF) + (g[(y + 1) * w + x].toInt() and 0xFF) - 4 * c
            sum += l; sum2 += l.toDouble() * l; n++
        }
        if (n == 0) return 0.0
        val m = sum / n
        return sum2 / n - m * m
    }

    fun mean(g: ByteArray): Double { var s = 0L; for (b in g) s += b.toInt() and 0xFF; return s.toDouble() / max(1, g.size) }

    fun saturatedFraction(g: ByteArray): Double { var n = 0; for (b in g) if ((b.toInt() and 0xFF) >= 250) n++; return n.toDouble() / max(1, g.size) }
}
