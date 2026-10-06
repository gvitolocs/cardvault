# Original Android scanner pack (bundled, binaries not in Git)

The 2026-10-06 Pokoin API/scanning document specifies local Android recognition:
bundle the original detector, Android CNN and matching Pokémon galleries in the
APK, then copy them to private application support `fast_scan/`. Do not train
replacement models, mix in the iOS Core ML indices, or assume a CDN model URL.

## Source and packaging

The user supplied `pokoin-android-scan-assets.zip` on 2026-10-06, SHA256
`6D2FD4787CD4D5277A49D5DC9994B1FF370034DC1B1ACA89494A2CD2EAE3046D`.
Original Android files were extracted without overwriting existing files, with
per-file archive/extraction checksum verification. These directories remain
gitignored; a fresh checkout must obtain the original pack separately.

`pubspec.yaml` explicitly packages:

- `assets/models/card_detector.tflite` (5,327,632 bytes)
- `assets/models/milo_cnn.onnx` (9,524,623 bytes)
- `assets/milo_cnn_index/{western,japanese,chinese}/`, each containing
  `embeddings.bin`, `metadata.jsonl`, and `manifest.json`

The supplied `milo.onnx` and `milo_fp16.onnx` are retained locally but are not
needed or bundled by this Android CNN path. The ZIP's Core ML package is not
imported into the Android app. CNN model SHA256:
`ED690F760718ECDF8C0D106E3255840C42F3C5C1D32852E95037DE50857CA13A`.

| Gallery | Rows | Dimension | Embedding bytes |
| --- | ---: | ---: | ---: |
| western | 26689 | 128 | 13664768 |
| japanese | 24067 | 128 | 12322304 |
| chinese | 10956 | 128 | 5609472 |

All three manifests use `mobilenet_v2_448_128`, `identity: ct_id`, and
`cdn_cnn_v22_<gallery>`. Keep the existing `ct_id × 2` canonical-card lookup;
do not multiply a server `public_id` or TCGPlayer id.

## Automatic provisioning and recovery

`ScanAssetGate` prepares the default western pack automatically. A complete
pack opens the camera without a setup/download screen. Missing files or copy
errors show a compact recoverable error, expandable technical details, and
retry; shared app navigation remains available.

`ScanAssetStore.prepareAndroidBundle` stages the entire selected pack in
private storage, validates the Android CNN manifest, matrix length, metadata
row count and numeric ids, then publishes files and writes the APK revision
last. Missing/invalid source files do not replace an existing pack. On a repeat
open, a validated cache for the same APK revision avoids copying the large
models again; corrupted gallery data is repaired from the bundle. Native
`bundleStamp` includes install/update time as well as version code, because
successive debug APKs can share version `1.0.0+58`.

The same provisioning runs before native initialization and gallery changes,
so Japanese/Chinese packs are copied only when selected. Native initialization
has a 60-second UI timeout, without pretending to cancel native work; first
detection has a 30-second watchdog. Engine errors remain visible independently
of camera initialization. Real recognition still requires an on-device test,
not just a successful file-copy test.

The pre-existing explicit `ScanEngine.downloadAssets` utility remains available
for future operator-approved integrations, but the mobile scanner does not call
it and no CDN address or download build flag is configured. Remote photo
recognition (`/api/scan/identify`) is a separate API path, not a silent fallback.
