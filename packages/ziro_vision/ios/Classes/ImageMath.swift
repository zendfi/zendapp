import Foundation

/// Mirrors `lib/src/stub_reference.dart` and `android/.../ImageMath.kt` step by step.
enum ImageMath {
    static let roi = 224
    static let flash = 96
    private static let tiles = 8
    private static let tile = 28
    private static let tilePixels = 784
    private static let clip = 6

    struct P { var x: Double; var y: Double }

    static func luma(_ r: Int, _ g: Int, _ b: Int) -> Int { (77 * r + 150 * g + 29 * b) >> 8 }

    static func palmQuad(_ p: [P]) -> [P] {
        let p0 = p[0], p5 = p[5], p9 = p[9], p17 = p[17]
        return [p5, p17,
                P(x: p0.x + 0.8 * (p17.x - p9.x), y: p0.y + 0.8 * (p17.y - p9.y)),
                P(x: p0.x + 0.8 * (p5.x - p9.x), y: p0.y + 0.8 * (p5.y - p9.y))]
    }

    static func homography(_ quad: [P], _ size: Int) -> [Double]? {
        let s = Double(size - 1)
        let dst = [P(x: 0, y: 0), P(x: s, y: 0), P(x: s, y: s), P(x: 0, y: s)]
        var a = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for k in 0..<4 {
            let u = dst[k].x, v = dst[k].y, x = quad[k].x, y = quad[k].y
            a[2 * k] = [u, v, 1, 0, 0, 0, -u * x, -v * x, x]
            a[2 * k + 1] = [0, 0, 0, u, v, 1, -u * y, -v * y, y]
        }
        for col in 0..<8 {
            var piv = col
            for r in (col + 1)..<8 where abs(a[r][col]) > abs(a[piv][col]) { piv = r }
            if abs(a[piv][col]) < 1e-12 { return nil }
            a.swapAt(col, piv)
            for r in 0..<8 where r != col {
                let f = a[r][col] / a[col][col]
                if f == 0 { continue }
                for c in col..<9 { a[r][c] -= f * a[col][c] }
            }
        }
        return (0..<8).map { a[$0][8] / a[$0][$0] }
    }

    static func sample(_ img: [UInt8], _ w: Int, _ h: Int, _ x: Double, _ y: Double) -> UInt8 {
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - Double(x0), fy = y - Double(y0)
        func px(_ xx: Int, _ yy: Int) -> Double { Double(img[min(max(yy, 0), h - 1) * w + min(max(xx, 0), w - 1)]) }
        let v = (1 - fy) * ((1 - fx) * px(x0, y0) + fx * px(x0 + 1, y0)) + fy * ((1 - fx) * px(x0, y0 + 1) + fx * px(x0 + 1, y0 + 1))
        return UInt8(min(max(Int(floor(v + 0.5)), 0), 255))
    }

    static func warpGray(_ img: [UInt8], _ w: Int, _ h: Int, _ quad: [P], _ size: Int) -> [UInt8]? {
        guard let m = homography(quad, size) else { return nil }
        var out = [UInt8](repeating: 0, count: size * size)
        for v in 0..<size { for u in 0..<size {
            let du = Double(u), dv = Double(v)
            let den = m[6] * du + m[7] * dv + 1
            out[v * size + u] = sample(img, w, h, (m[0] * du + m[1] * dv + m[2]) / den, (m[3] * du + m[4] * dv + m[5]) / den)
        } }
        return out
    }

    static func warpRgb(_ rgb: [UInt8], _ w: Int, _ h: Int, _ quad: [P], _ size: Int) -> [UInt8]? {
        guard let m = homography(quad, size) else { return nil }
        let ch = (0..<3).map { c in (0..<(w * h)).map { rgb[$0 * 3 + c] } }
        var out = [UInt8](repeating: 0, count: size * size * 3)
        for v in 0..<size { for u in 0..<size {
            let du = Double(u), dv = Double(v)
            let den = m[6] * du + m[7] * dv + 1
            let x = (m[0] * du + m[1] * dv + m[2]) / den, y = (m[3] * du + m[4] * dv + m[5]) / den
            for c in 0..<3 { out[(v * size + u) * 3 + c] = sample(ch[c], w, h, x, y) }
        } }
        return out
    }

    private static func tileIndex(_ f: Double) -> (Int, Int, Double) {
        let i = Int(floor(f))
        if i < 0 { return (0, 0, 0) }
        if i >= tiles - 1 { return (tiles - 1, tiles - 1, 0) }
        return (i, i + 1, f - Double(i))
    }

    static func clahe(_ gray: [UInt8]) -> [UInt8] {
        var luts = [[Int]](repeating: [Int](repeating: 0, count: 256), count: tiles * tiles)
        for ty in 0..<tiles { for tx in 0..<tiles {
            var hist = [Int](repeating: 0, count: 256)
            for y in (ty * tile)..<((ty + 1) * tile) { for x in (tx * tile)..<((tx + 1) * tile) { hist[Int(gray[y * roi + x])] += 1 } }
            var excess = 0
            for b in 0..<256 where hist[b] > clip { excess += hist[b] - clip; hist[b] = clip }
            let inc = excess / 256, rem = excess % 256
            for b in 0..<256 { hist[b] += inc + (b < rem ? 1 : 0) }
            var cdf = 0
            for b in 0..<256 { cdf += hist[b]; luts[ty * tiles + tx][b] = min(255, (cdf * 255) / tilePixels) }
        } }
        var out = [UInt8](repeating: 0, count: gray.count)
        for y in 0..<roi {
            let (y0, y1, ay) = tileIndex((Double(y) + 0.5) / Double(tile) - 0.5)
            for x in 0..<roi {
                let (x0, x1, ax) = tileIndex((Double(x) + 0.5) / Double(tile) - 0.5)
                let p = Int(gray[y * roi + x])
                let l00 = Double(luts[y0 * tiles + x0][p]), l01 = Double(luts[y0 * tiles + x1][p])
                let l10 = Double(luts[y1 * tiles + x0][p]), l11 = Double(luts[y1 * tiles + x1][p])
                let v = (1 - ay) * ((1 - ax) * l00 + ax * l01) + ay * ((1 - ax) * l10 + ax * l11)
                out[y * roi + x] = UInt8(min(max(Int(floor(v + 0.5)), 0), 255))
            }
        }
        return out
    }

    private static let pairs: [(Int, Int)] = [
        (1, 2), (2, 3), (3, 4), (5, 6), (6, 7), (7, 8), (9, 10), (10, 11), (11, 12), (13, 14), (14, 15), (15, 16),
        (17, 18), (18, 19), (19, 20), (0, 1), (0, 5), (0, 9), (0, 13), (0, 17), (5, 9), (9, 13), (13, 17), (2, 5),
    ]

    static func geometry(_ p: [P]) -> [Double] {
        func d(_ a: Int, _ b: Int) -> Double { hypot(p[a].x - p[b].x, p[a].y - p[b].y) }
        let w = d(5, 17)
        if w <= 0 { return [Double](repeating: 0, count: 24) }
        return pairs.map { d($0.0, $0.1) / w }
    }

    static func laplacianVariance(_ g: [UInt8], _ w: Int, _ h: Int) -> Double {
        var s = 0.0, s2 = 0.0, n = 0.0
        for y in 1..<(h - 1) { for x in 1..<(w - 1) {
            let c = Int(g[y * w + x])
            let l = Double(Int(g[y * w + x - 1]) + Int(g[y * w + x + 1]) + Int(g[(y - 1) * w + x]) + Int(g[(y + 1) * w + x]) - 4 * c)
            s += l; s2 += l * l; n += 1
        } }
        guard n > 0 else { return 0 }
        let m = s / n
        return s2 / n - m * m
    }

    static func mean(_ g: [UInt8]) -> Double { g.isEmpty ? 0 : Double(g.reduce(0) { $0 + Int($1) }) / Double(g.count) }
    static func saturated(_ g: [UInt8]) -> Double { g.isEmpty ? 0 : Double(g.filter { $0 >= 250 }.count) / Double(g.count) }
}

/// SplitMix64 + Box-Muller (stub_reference.dart).
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextDouble() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
}

enum Stub {
    static let palmSeed: UInt64 = 0x5A49524F
    static let faceSeed: UInt64 = 0x46414345

    static func matrix(seed: UInt64, rows: Int) -> [Float] {
        var rng = SplitMix64(state: seed)
        var spare: Double?
        var out = [Float](repeating: 0, count: rows * 1024)
        for k in 0..<out.count {
            if let s = spare { out[k] = Float(s); spare = nil; continue }
            let u1 = 1.0 - rng.nextDouble(), u2 = rng.nextDouble()
            let r = sqrt(-2.0 * log(u1)), t = 2.0 * Double.pi * u2
            spare = r * sin(t)
            out[k] = Float(r * cos(t))
        }
        return out
    }

    static func embed(_ eq: [UInt8], _ m: [Float], _ dims: Int) -> [Float] {
        var x = [Double](repeating: 0, count: 1024)
        for r in 0..<32 { for c in 0..<32 {
            var s = 0
            for dy in 0..<7 { let row = (r * 7 + dy) * 224 + c * 7; for dx in 0..<7 { s += Int(eq[row + dx]) } }
            x[r * 32 + c] = Double(s) / 49.0
        } }
        let mean = x.reduce(0, +) / 1024
        var std = sqrt(x.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / 1024)
        if std < 1e-6 { std = 1 }
        let z = x.map { ($0 - mean) / std }
        var y = [Double](repeating: 0, count: dims), n2 = 0.0
        for i in 0..<dims {
            var acc = 0.0
            let base = i * 1024
            for j in 0..<1024 { acc += Double(m[base + j]) * z[j] }
            y[i] = acc; n2 += acc * acc
        }
        if n2 == 0 { return [Float](repeating: 0, count: dims) }
        let n = sqrt(n2)
        return y.map { Float($0 / n) }
    }

    static func average(_ vs: [[Float]]) -> [Float] {
        let dims = vs[0].count
        var acc = [Double](repeating: 0, count: dims)
        for v in vs { for i in 0..<dims { acc[i] += Double(v[i]) } }
        let n = sqrt(acc.reduce(0) { $0 + $1 * $1 })
        return n == 0 ? [Float](repeating: 0, count: dims) : acc.map { Float($0 / n) }
    }
}

enum F16 {
    static func encode(_ v: [Float]) -> Data {
        var d = Data(capacity: v.count * 2)
        for f in v { let h = Float16(f).bitPattern; d.append(UInt8(h & 0xFF)); d.append(UInt8(h >> 8)) }
        return d
    }
}
