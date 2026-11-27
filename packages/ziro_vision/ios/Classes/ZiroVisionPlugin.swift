import AVFoundation
import CryptoKit
import DeviceCheck
import Flutter
import MediaPipeTasksVision
import TensorFlowLite
import UIKit

/// iOS side of `zend/ziro_vision` (contracts §6). Same capture logic as Android's
/// CaptureSession.kt. Full frames stay in this file.
public class ZiroVisionPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, FlutterTexture,
    AVCaptureVideoDataOutputSampleBufferDelegate {
    private var sink: FlutterEventSink?
    private let textures: FlutterTextureRegistry
    private let registrar: FlutterPluginRegistrar
    private var textureId: Int64 = 0
    private var latest: CVPixelBuffer?
    private let latestLock = NSLock()
    private let queue = DispatchQueue(label: "ziro.vision")
    private var session: AVCaptureSession?
    private var device: AVCaptureDevice?
    private var hands: HandLandmarker?
    private var faces: FaceDetector?
    private var palmMatrix: [Float] = []
    private var faceMatrix: [Float] = []
    private var palmModel: Interpreter?
    private var palmVersion = "palm-0"
    private var faceVersion = "face-0"

    // Capture state (queue only).
    private enum Phase { case idle, neutral, flash, done }
    private var phase = Phase.idle
    private var mode = "pay"
    private var wantHands: [String] = ["left", "right"]
    private var wantFace = false
    private var colours = 0
    private var colourMs = 120
    private var deadline = Date()
    private var good: [(Double, [Float])] = []
    private var geometry: [[Double]] = []
    private var palmsDone: [[String: String]] = []
    private var neutralCrops: [String] = []
    private var flashFrames: [[String: String]] = []
    private var track: [[String: String]] = []
    private var shown: [[String: Any]] = []
    private var faceVecs: [[Float]] = []
    private var flashStartUs: Int64 = 0
    private var lastGuide = ""
    private var lastQuad: [ImageMath.P]?

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        self.textures = registrar.textures()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let p = ZiroVisionPlugin(registrar: registrar)
        let m = FlutterMethodChannel(name: "zend/ziro_vision", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(p, channel: m)
        FlutterEventChannel(name: "zend/ziro_vision/events", binaryMessenger: registrar.messenger()).setStreamHandler(p)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { sink = events; return nil }
    public func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }

    private func post(_ m: [String: Any?]) { DispatchQueue.main.async { self.sink?(m.compactMapValues { $0 ?? NSNull() }) } }

    /// Host-time microseconds: the same clock for frames (presentation timestamps on the host
    /// clock) and for `flashShown`.
    private static func nowUs() -> Int64 { Int64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * 1_000_000) }

    private func asset(_ name: String) -> String? {
        let key = registrar.lookupKey(forAsset: "assets/models/\(name)", fromPackage: "ziro_vision")
        return Bundle.main.path(forResource: key, ofType: nil)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "prepare": queue.async { self.prepare(result) }
        case "openPreview": openPreview(result)
        case "closePreview":
            queue.async { if self.phase != .neutral && self.phase != .flash { self.session?.stopRunning() } }
            result(nil)
        case "startCapture": queue.async { self.start(args) }; result(nil)
        case "flashShown":
            let t = Self.nowUs(), i = args["index"] as? Int ?? -1
            queue.async { if i == -1 && self.flashStartUs == 0 { self.flashStartUs = t }; self.shown.append(["index": i, "t_us": String(t)]) }
            result(nil)
        case "stopCapture": queue.async { self.reset(); self.phase = .idle; self.lock(false) }; result(nil)
        case "deviceKeyCreate": deviceKeyCreate(args, result)
        case "deviceKeySign": deviceKeySign(args, result)
        case "integrityToken": integrityToken(args, result)
        default: result(FlutterMethodNotImplemented)
        }
    }

    // MARK: models

    private func prepare(_ result: @escaping FlutterResult) {
        do {
            if hands == nil {
                guard let path = asset("hand_landmarker.task") else { throw NSError(domain: "ziro", code: 1) }
                let o = HandLandmarkerOptions()
                o.baseOptions.modelAssetPath = path
                o.runningMode = .video
                o.numHands = 1
                hands = try HandLandmarker(options: o)
                if let fp = asset("blaze_face_short_range.tflite") {
                    let fo = FaceDetectorOptions()
                    fo.baseOptions.modelAssetPath = fp
                    fo.runningMode = .video
                    faces = try? FaceDetector(options: fo)
                }
                if let mp = asset("palm_embedding.tflite") {
                    let delegate = CoreMLDelegate()
                    palmModel = try Interpreter(modelPath: mp, delegates: delegate.map { [$0] } ?? [])
                    try palmModel?.allocateTensors()
                    if let jp = asset("palm_embedding.json"), let d = FileManager.default.contents(atPath: jp),
                       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        palmVersion = j["model_version"] as? String ?? "palm-0"
                    }
                } else {
                    palmMatrix = Stub.matrix(seed: Stub.palmSeed, rows: 256)
                }
                if faces != nil { faceMatrix = Stub.matrix(seed: Stub.faceSeed, rows: 512) }
            }
            _ = embedPalm([UInt8](repeating: 0, count: 224 * 224))
            let r: [String: Any?] = ["model_version": palmVersion, "face_model_version": faces != nil ? faceVersion : nil]
            DispatchQueue.main.async { result(r.compactMapValues { $0 ?? NSNull() }) }
        } catch {
            DispatchQueue.main.async { result(FlutterError(code: "model_failed", message: "\(error)", details: nil)) }
        }
    }

    private func embedPalm(_ gray: [UInt8]) -> [Float] {
        let eq = ImageMath.clahe(gray)
        if let m = palmModel {
            var input = eq.map { Float($0) / 255 }
            let data = Data(bytes: &input, count: input.count * 4)
            if (try? m.copy(data, toInputAt: 0)) != nil, (try? m.invoke()) != nil, let out = try? m.output(at: 0) {
                let v = out.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                let n = sqrt(v.reduce(0) { $0 + $1 * $1 })
                return n > 0 ? v.map { $0 / n } : v
            }
        }
        return Stub.embed(eq, palmMatrix, 256)
    }

    // MARK: camera

    private func openPreview(_ result: @escaping FlutterResult) {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { DispatchQueue.main.async { result(FlutterError(code: "camera_denied", message: nil, details: nil)) }; return }
            self.queue.async {
                do {
                    if self.session == nil { try self.configure() }
                    self.session?.startRunning()
                    DispatchQueue.main.async {
                        if self.textureId == 0 { self.textureId = self.textures.register(self) }
                        result(["texture_id": self.textureId, "width": 1280, "height": 720, "quarter_turns": 0, "mirror": true])
                    }
                } catch {
                    DispatchQueue.main.async { result(FlutterError(code: "camera_failed", message: "\(error)", details: nil)) }
                }
            }
        }
    }

    private func configure() throws {
        let s = AVCaptureSession()
        s.sessionPreset = .hd1280x720
        guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { throw NSError(domain: "ziro", code: 2) }
        let input = try AVCaptureDeviceInput(device: d)
        s.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        s.addOutput(out)
        if let c = out.connection(with: .video) {
            if c.isVideoMirroringSupported { c.isVideoMirrored = true }
            if #available(iOS 17.0, *) { if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 } }
            else if c.isVideoOrientationSupported { c.videoOrientation = .portrait }
        }
        try d.lockForConfiguration()
        d.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        d.unlockForConfiguration()
        session = s
        device = d
    }

    private func lock(_ on: Bool) {
        guard let d = device, (try? d.lockForConfiguration()) != nil else { return }
        if on {
            if d.isExposureModeSupported(.locked) { d.exposureMode = .locked }
            if d.isWhiteBalanceModeSupported(.locked) { d.whiteBalanceMode = .locked }
        } else {
            if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
            if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { d.whiteBalanceMode = .continuousAutoWhiteBalance }
        }
        d.unlockForConfiguration()
    }

    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        latestLock.lock(); defer { latestLock.unlock() }
        guard let b = latest else { return nil }
        return Unmanaged.passRetained(b)
    }

    // MARK: capture

    private func start(_ a: [String: Any]) {
        mode = a["mode"] as? String ?? "pay"
        wantHands = a["hands"] as? [String] ?? ["left", "right"]
        wantFace = (a["face"] as? Bool ?? false) && faces != nil
        colours = (a["colours"] as? [String])?.count ?? 0
        colourMs = a["colour_ms"] as? Int ?? 120
        deadline = Date().addingTimeInterval(Double(a["timeout_ms"] as? Int ?? 30000) / 1000)
        reset(); palmsDone = []
        lock(false)
        phase = .neutral
    }

    private func reset() {
        good = []; geometry = []; neutralCrops = []; flashFrames = []; track = []; shown = []; faceVecs = []
        flashStartUs = 0; lastGuide = ""; lastQuad = nil
    }

    private func guide(_ c: String) { if c != lastGuide { lastGuide = c; post(["type": "guide", "code": c]) } }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        latestLock.lock(); latest = pb; latestLock.unlock()
        DispatchQueue.main.async { if self.textureId != 0 { self.textures.textureFrameAvailable(self.textureId) } }
        guard phase == .neutral || phase == .flash else { return }
        if Date() > deadline { phase = .idle; lock(false); post(["type": "error", "code": "timeout"]); return }
        let tUs = Int64(CMSampleBufferGetPresentationTimeStamp(sb).seconds * 1_000_000)
        // 640-wide working copy, RGB.
        let (rgb, w, h) = downscaledRGB(pb, maxSide: 640)
        guard let img = try? MPImage(sampleBuffer: sb), let res = try? hands?.detect(videoFrame: img, timestampInMilliseconds: Int(tUs / 1000)) else { return }
        guard let lm = res.landmarks.first else {
            if phase == .neutral { guide("show_palm") }
            if phase == .flash { flashFrame(tUs, rgb, w, h, nil, nil) }
            return
        }
        let pts = lm.map { ImageMath.P(x: Double($0.x) * Double(w), y: Double($0.y) * Double(h)) }
        let handed = res.handedness.first?.first?.categoryName?.lowercased() ?? ""
        var tr = [Float](repeating: 0, count: 63)
        for (i, p) in lm.enumerated() { tr[i * 3] = p.x; tr[i * 3 + 1] = p.y; tr[i * 3 + 2] = p.z }
        if phase == .neutral { neutral(tUs, rgb, w, h, pts, handed, img) } else { flashFrame(tUs, rgb, w, h, pts, tr) }
    }

    private func downscaledRGB(_ pb: CVPixelBuffer, maxSide: Int) -> ([UInt8], Int, Int) {
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let sw = CVPixelBufferGetWidth(pb), sh = CVPixelBufferGetHeight(pb), stride = CVPixelBufferGetBytesPerRow(pb)
        let step = max(1, max(sw, sh) / maxSide)
        let w = sw / step, h = sh / step
        guard let base = CVPixelBufferGetBaseAddress(pb)?.assumingMemoryBound(to: UInt8.self) else { return ([], 0, 0) }
        var out = [UInt8](repeating: 0, count: w * h * 3)
        for y in 0..<h { for x in 0..<w {
            let s = (y * step) * stride + (x * step) * 4, o = (y * w + x) * 3
            out[o] = base[s + 2]; out[o + 1] = base[s + 1]; out[o + 2] = base[s]
        } }
        return (out, w, h)
    }

    private func gray(_ rgb: [UInt8], _ n: Int) -> [UInt8] {
        (0..<n).map { UInt8(ImageMath.luma(Int(rgb[$0 * 3]), Int(rgb[$0 * 3 + 1]), Int(rgb[$0 * 3 + 2]))) }
    }

    private func b64(_ d: Data) -> String { d.base64EncodedString() }

    private func neutral(_ tUs: Int64, _ rgb: [UInt8], _ w: Int, _ h: Int, _ pts: [ImageMath.P], _ handed: String, _ img: MPImage) {
        guard let target = wantHands.first else { return }
        if mode == "enroll" && !handed.isEmpty && handed != target { guide("other_hand"); return }
        let width = hypot(pts[5].x - pts[17].x, pts[5].y - pts[17].y), side = Double(min(w, h))
        if width < 0.12 * side { guide("move_closer"); return }
        if width > 0.45 * side { guide("move_back"); return }
        let cross = (pts[5].x - pts[0].x) * (pts[17].y - pts[0].y) - (pts[5].y - pts[0].y) * (pts[17].x - pts[0].x)
        if !handed.isEmpty && !(handed == "left" ? cross < 0 : cross > 0) { guide("show_palm"); return }
        let quad = ImageMath.palmQuad(pts)
        guard let crop = ImageMath.warpGray(gray(rgb, w * h), w, h, quad, 224) else { return }
        if ImageMath.mean(crop) < 40 { guide("too_dark"); return }
        if ImageMath.saturated(crop) > 0.08 { guide("too_bright"); return }
        let sharp = ImageMath.laplacianVariance(crop, 224, 224)
        if sharp < 25 { guide("hold_still"); return }
        guide("ok")
        lastQuad = quad
        good.append((sharp, embedPalm(crop)))
        geometry.append(ImageMath.geometry(pts))
        if wantFace && faceVecs.count < 4, let det = try? faces?.detect(videoFrame: img, timestampInMilliseconds: Int(tUs / 1000)).detections.first {
            let b = det.boundingBox, s = Double(max(b.width, b.height)) * 1.2, cx = Double(b.midX), cy = Double(b.midY)
            let q = [ImageMath.P(x: cx - s / 2, y: cy - s / 2), ImageMath.P(x: cx + s / 2, y: cy - s / 2),
                     ImageMath.P(x: cx + s / 2, y: cy + s / 2), ImageMath.P(x: cx - s / 2, y: cy + s / 2)]
            if let fc = ImageMath.warpGray(gray(rgb, w * h), w, h, q, 224) { faceVecs.append(Stub.embed(ImageMath.clahe(fc), faceMatrix, 512)) }
        }
        if mode == "pay" && neutralCrops.count < 2, let c = ImageMath.warpRgb(rgb, w, h, quad, 96) { neutralCrops.append(b64(Data(c))) }
        guard good.count >= 8 else { return }
        let best = good.sorted { $0.0 > $1.0 }.prefix(8).map { $0.1 }
        palmsDone.append(["hand": handed.isEmpty ? target : handed, "embedding": b64(F16.encode(Stub.average(Array(best))))])
        good = []
        wantHands.removeFirst()
        if mode == "enroll" {
            post(["type": "hand_done", "hand": target])
            if wantHands.isEmpty { finish(nil) } else { lastGuide = "" }
            return
        }
        lock(true)
        phase = .flash
        post(["type": "ready_for_flash"])
    }

    private func flashFrame(_ tUs: Int64, _ rgb: [UInt8], _ w: Int, _ h: Int, _ pts: [ImageMath.P]?, _ tr: [Float]?) {
        if let p = pts { lastQuad = ImageMath.palmQuad(p) }
        guard let quad = lastQuad else { return }
        if flashStartUs != 0 && tUs >= flashStartUs {
            if let c = ImageMath.warpRgb(rgb, w, h, quad, 96) { flashFrames.append(["t_us": String(tUs), "rgb": b64(Data(c))]) }
            if let t = tr { track.append(["t_us": String(tUs), "points": b64(F16.encode(t))]) }
        }
        let end = flashStartUs + Int64((colours + 1) * colourMs) * 1000 + 250_000
        if flashStartUs != 0 && (tUs > end || flashFrames.count >= 30) {
            finish(["neutral": neutralCrops, "frames": flashFrames, "shown": shown, "landmarks": track])
        }
    }

    private func finish(_ flash: [String: Any]?) {
        phase = .done
        lock(false)
        var geo = [Double](repeating: 0, count: 24)
        for g in geometry { for i in 0..<24 { geo[i] += g[i] / Double(geometry.count) } }
        let face = faceVecs.isEmpty ? nil : b64(F16.encode(Stub.average(faceVecs)))
        var ev: [String: Any?] = ["type": "captured", "model_version": palmVersion + (face != nil ? "+\(faceVersion)" : ""),
                                  "palms": palmsDone, "geometry": b64(F16.encode(geo.map { Float($0) })), "face": face]
        if let f = flash { ev["flash"] = f }
        post(ev)
        reset()
    }

    // MARK: device key and App Attest

    private func deviceKeyCreate(_ a: [String: Any], _ result: @escaping FlutterResult) {
        guard let alias = a["alias"] as? String, let ch = (a["challenge"] as? String).flatMap({ Data(base64Encoded: $0) }) else {
            result(FlutterError(code: "key_failed", message: "bad arguments", details: nil)); return
        }
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey()
            UserDefaults.standard.set(key.dataRepresentation, forKey: "ziro.dev.\(alias)")
            let pub = key.publicKey.x963Representation
            let svc = DCAppAttestService.shared
            guard svc.isSupported else { result(FlutterError(code: "key_failed", message: "App Attest unsupported", details: nil)); return }
            svc.generateKey { keyId, err in
                guard let keyId = keyId, err == nil else { DispatchQueue.main.async { result(FlutterError(code: "key_failed", message: "\(String(describing: err))", details: nil)) }; return }
                // The registration challenge is already a 32-byte hash; it is the client data hash.
                svc.attestKey(keyId, clientDataHash: ch) { att, err in
                    DispatchQueue.main.async {
                        guard let att = att, err == nil else { result(FlutterError(code: "key_failed", message: "\(String(describing: err))", details: nil)); return }
                        UserDefaults.standard.set(keyId, forKey: "ziro.attest.\(alias)")
                        result(["public_key": pub.base64EncodedString(),
                                "ios": ["key_id": keyId, "attestation_object": att.base64EncodedString(), "client_data_hash": ch.base64EncodedString()]])
                    }
                }
            }
        } catch { result(FlutterError(code: "key_failed", message: "\(error)", details: nil)) }
    }

    private func deviceKeySign(_ a: [String: Any], _ result: @escaping FlutterResult) {
        guard let alias = a["alias"] as? String, let data = (a["data"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let raw = UserDefaults.standard.data(forKey: "ziro.dev.\(alias)"),
              let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: raw),
              let sig = try? key.signature(for: data) else {
            result(FlutterError(code: "key_failed", message: "no device key", details: nil)); return
        }
        result(["signature": sig.derRepresentation.base64EncodedString()])
    }

    private func integrityToken(_ a: [String: Any], _ result: @escaping FlutterResult) {
        guard let hash = (a["request_hash"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let keyId = UserDefaults.standard.string(forKey: "ziro.attest.ziro_device") else {
            result(FlutterError(code: "integrity_failed", message: "no attested key", details: nil)); return
        }
        DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: hash) { assertion, err in
            DispatchQueue.main.async {
                guard let assertion = assertion, err == nil else { result(FlutterError(code: "integrity_failed", message: "\(String(describing: err))", details: nil)); return }
                result(["assertion": assertion.base64EncodedString(), "client_data_hash": hash.base64EncodedString()])
            }
        }
    }
}
