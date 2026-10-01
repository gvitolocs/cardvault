# On-device scan assets (runtime-managed, not in git)

Pokoin does not bundle the large scan models or embedding galleries. The user
selects the pack(s) to download, and the app stores them under its application
support directory in `fast_scan/`.

Required at runtime:

- `card_detector.tflite`
- either `milo.onnx` or `milo_cnn.onnx`
- `<gallery>/embeddings.bin`
- `<gallery>/metadata.jsonl`
- `<gallery>/manifest.json`

`gallery` is one of `western`, `japanese`, or `chinese`. `milo_fp16.onnx` is
optional and is used by the Android acceleration preparation path.

The runtime download entry point is `ScanEngine.downloadAssets`. Pass only the
files selected by the user, using paths relative to the scan root, then call
`ScanEngine.assetStatus(gallery: ...)` before starting the camera.

Sync from pokoin-cardapp before Android release builds on nezopt:

```bash
rsync -a --delete \
  /home/nez/Projects/pokoin-cardapp/flutter/assets/models/ \
  /home/nez/Projects/cardvault/pokemon_card_vault/assets/models/
rsync -a --delete \
  /home/nez/Projects/pokoin-cardapp/flutter/assets/milo_index/ \
  /home/nez/Projects/cardvault/pokemon_card_vault/assets/milo_index/
rsync -a --delete \
  /home/nez/Projects/pokoin-cardapp/flutter/assets/milo_cnn_index/ \
  /home/nez/Projects/cardvault/pokemon_card_vault/assets/milo_cnn_index/
```

Release AAB (nezopt): `dist/pokoin-1.0.0+58.aab`
