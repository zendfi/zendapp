# ziro_vision

Palm capture for Ziro (contracts.md §6): front camera, MediaPipe hand landmarks, quality gate,
palm crop, on-device templates, the flash clip for liveness, a hardware P-256 device key, and
per-charge integrity (Play Integrity / App Attest). Raw camera frames never leave native code;
Dart receives templates, 96×96 flash crops and events only.

## Model assets

Put these in `assets/models/` (see `MODELS.md`):

| File | Needed | Source |
|---|---|---|
| `hand_landmarker.task` | yes | https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task |
| `blaze_face_short_range.tflite` | face opt-in only | https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/latest/blaze_face_short_range.tflite |
| `palm_embedding.tflite` + `.json` | optional | `ziro/ml/ziro_ml/export.py`; without it the stub `palm-0` runs |
| `face_embedding.tflite` + `.json` | optional | licensed face model; without it the stub `face-0` runs |

## Stub embeddings

`palm-0` and `face-0` are deterministic random projections, identical on Android, iOS and
`lib/src/stub_reference.dart`: CLAHE (8×8 tiles, clip 6) → 7×7 box mean to 32×32 → mean/std
normalise → multiply by a Gaussian matrix (SplitMix64, seed `0x5A49524F` palm / `0x46414345`
face, Box-Muller using both outputs) → L2 normalise. Good enough for the whole flow in test
mode; not a biometric.

## Hand geometry (24 values)

Distances between landmark pairs over palm width |P5 − P17|: finger segments (1-2, 2-3, 3-4,
5-6, 6-7, 7-8, 9-10, 10-11, 11-12, 13-14, 14-15, 15-16, 17-18, 18-19, 19-20), palm lengths
(0-1, 0-5, 0-9, 0-13, 0-17), widths (5-9, 9-13, 13-17, 2-5).

## Capture

- Neutral phase: 8 frames that pass the gate (palm width 12–45% of the short side, palm
  facing, mean ≥ 40, < 8% saturated, Laplacian variance ≥ 25). Best 8 embeddings by sharpness
  are averaged. Two 96×96 neutral RGB crops are kept in pay mode.
- Then exposure and white balance lock (Camera2 `CONTROL_AE_LOCK`/`AWB_LOCK`; AVFoundation
  `.locked`), `ready_for_flash` goes out, and Dart paints white then each colour, calling
  `flashShown(index)` after each paint.
- Flash phase: 96×96 crops and landmark tracks until all colours plus 250 ms have passed
  (max 30 frames). Locks are released after.
- Clocks: Android frames and `flashShown` both use `elapsedRealtime` (sensor timestamps on the
  uptime clock are shifted); iOS uses host time for both.

## Device key and integrity

- Android: Keystore P-256 with `setAttestationChallenge` (StrongBox when available). Play
  Integrity standard requests; set
  `<meta-data android:name="com.zend.ziro.cloud_project_number" android:value="…"/>` in the
  app manifest. `requestHash` is base64url without padding of the 32-byte hash.
- iOS: Secure Enclave P-256 signing key plus an App Attest key, attested with the registration
  challenge as the client data hash. Per-charge assertions use the App Attest key. Needs the
  App Attest capability (`com.apple.developer.devicecheck.appattest-environment`).

## App setup

- Android: `CAMERA` permission (already in Zend's manifest); app `minSdk` 24.
- iOS: `NSCameraUsageDescription` = "Zend uses the camera to read your palm for payments.";
  iOS 15+; arm64 (uses `Float16`).

## Needs a real device

Everything native: camera locks, landmark quality thresholds, palm-facing sign, preview
rotation, timing alignment and integrity. The Dart side and the stub math are unit-tested.
