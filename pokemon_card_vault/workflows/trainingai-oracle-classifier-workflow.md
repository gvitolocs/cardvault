# TrainingAI Oracle Classifier Workflow

Use this workflow when moving Pokemon card recognition from Hugging Face free
tier to a lightweight Oracle VM.

## Roles

- Google Colab: generate or refresh `pokemon.index`, `metadata.json`, and
  `card_paths.json`.
- Oracle VM: run the small FastAPI classifier from
  `integrations/trainingai-oracle-api`.
- Cloudflare Worker on `trainingai.pokoin.com`: keep serving the CardVault image
  manifest and proxy `POST /api/classify` to the Oracle classifier through
  `TRAININGAI_CLASSIFIER_URL`.

## Current Target Choice

Use Oracle peer3 for the classifier unless a later probe shows otherwise:

```text
peer3 / pokoin-vm3
host: 141.147.62.244
ssh user: ubuntu
key: keys/peer3/ssh-key-2026-05-16.key
```

Peer3 was the lightest candidate in the latest probe:

```text
cpu: 2
memory: 15988 MB total, 14861 MB available
disk: 45 GB total, 33 GB available, 29% used
load: 0.00 0.01 0.00
docker: yes
```

Avoid peer4 for this classifier while it remains the marketplace Postgres
primary/ingestion host. Peer2 already runs Pokontact/Ollama. Peer1 has lower load
than peer2/peer4 but less free disk and more unrelated app containers than peer3.

## Hugging Face Access On Peer3

Peer3 has the Hugging Face CLI installed for the `ubuntu` user and is logged in
as:

```text
newisdom
```

The token is stored only in the Hugging Face local cache on peer3:

```text
/home/ubuntu/.cache/huggingface/token
/home/ubuntu/.cache/huggingface/stored_tokens
```

Do not copy token values into this repository or workflow docs. To verify access:

```bash
ssh -i /Users/giuseppe/pokoinpos/keys/peer3/ssh-key-2026-05-16.key \
  ubuntu@141.147.62.244 \
  'export PATH="$HOME/.local/bin:$PATH"; hf auth whoami'
```

If the token is rotated, rerun `hf auth login --token <token>` on peer3 and keep
the real token out of git and chat logs.

## Cloudflare Image Source

Wrangler can read Cloudflare using the local operator env. Do not print or commit
Cloudflare keys. The training image bucket is:

```text
bucket: cardvault-images
location: WEUR
objects: 214412
size: 15.6 GB
```

For Colab, prefer the public read-only manifest over direct R2 credentials:

```text
https://trainingai.pokoin.com/manifest.json?limit=1000
```

The manifest is paginated. Follow `nextCursor` while `hasMore` is true. Do not
try to load the full bucket into memory at once.

Each card can have multiple image resolutions. For embeddings/training, use only
high-resolution card images and skip generated derivatives. The current object
names commonly use `-full-v3` or `_full`, while homepage derivatives include
`_homepage.webp` and must be excluded even if the source name contains `full`.

Minimal Colab importer shape:

```python
import pathlib
import requests

out_dir = pathlib.Path("cardvault_images")
out_dir.mkdir(exist_ok=True)

def is_highres_card_key(key):
    key = key.lower()
    if not key.endswith((".jpg", ".jpeg", ".png", ".webp")):
        return False
    if any(part in key for part in (
        "_homepage.",
        "_homepage",
        "/previews/",
        "preview_",
        "artist-profiles/",
        "avatars/",
        "profile-pictures/",
        "user/",
        "users/",
    )):
        return False
    return "-full" in key or "_full" in key

cursor = None
downloaded = 0
max_images = 5000  # raise gradually after the pipeline is verified

while downloaded < max_images:
    params = {"limit": 1000}
    if cursor:
        params["cursor"] = cursor
    page = requests.get(
        "https://trainingai.pokoin.com/manifest.json",
        params=params,
        timeout=30,
    ).json()
    for obj in page["objects"]:
        if downloaded >= max_images:
            break
        if not is_highres_card_key(obj["key"]):
            continue
        target = out_dir / obj["key"].split("/")[-1]
        if not target.exists():
            image = requests.get(obj["url"], timeout=60)
            image.raise_for_status()
            target.write_bytes(image.content)
        downloaded += 1
    cursor = page.get("nextCursor") if page.get("hasMore") else None
    if not cursor:
        break
```

Start with a bounded sample, generate artifacts, deploy them to Oracle, then
scale the sample size. Full-bucket training/import is a separate batch job.

## Best Blueprint Image Manifest

For full classifier coverage, prefer the Oracle-derived manifest over the raw R2
object manifest:

```text
https://trainingai.pokoin.com/blueprints/best-images.json
```

This JSON is generated from `public.cardtrader_pokemon_blueprints` and contains
one best non-homepage image per CardTrader blueprint. It prefers
`cdn_object_key` from R2 and falls back to `cardtrader_image_url` /
`blueprint.image.url` when needed. The current shape is:

```json
{
  "generated_at": "...",
  "source": "oracle.public.cardtrader_pokemon_blueprints",
  "strategy": "one best non-homepage image per blueprint; prefer R2 object, fallback CardTrader source URL",
  "count": 72052,
  "objects": [
    {
      "blueprint_id": "104439",
      "object_key": "104439_...-full-v3.webp",
      "url": "https://trainingai.pokoin.com/images/104439_...-full-v3.webp",
      "source": "r2_full",
      "name": "...",
      "set_name": "Pokemon Products",
      "collector_number": ""
    }
  ]
}
```

Fallback CardTrader URLs can share generic basenames such as
`/fallbacks/card_uploader/preview.png`. Do not use that basename as a lookup key.
When a fallback/source URL has a generic basename, the generator must write a
stable logical `object_key` and `original_path` in the
`<blueprint_id>_<name-version-set-slug>.<source-ext>` format while keeping `url`
and `cardtrader_image_url` pointed at the real remote source unless the image has
actually been uploaded/copied to R2. Never publish a `trainingai.pokoin.com`
image URL for a normalized key until that object exists.

Regenerate it after blueprint image imports or CDN updates:

```bash
npm run trainingai:best-images -- --upload-r2
workflows/deploy-trainingai-cardvault-images.sh
curl -fsS https://trainingai.pokoin.com/blueprints/best-images.json \
  | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.parse(d).count))"
```

The generator reads `MARKETPLACE_DATABASE_URL` from `.env.local` by default and
writes `data/trainingai/best-blueprint-images.json`. With `--upload-r2`, it
publishes the manifest to
`cardvault-images/manifests/best-blueprint-images.json` through Wrangler/R2. Do
not commit generated manifest JSON unless explicitly needed for a fixture.

Colab resume jobs should read `/blueprints/best-images.json`, load existing
`metadata.json`, build a set of processed `blueprint_id` values, and skip those
IDs before downloading or embedding. This preserves already-generated artifacts
such as the initial 5,158-vector index and only appends missing blueprint
embeddings.

## Deploy Classifier

```bash
TRAININGAI_ORACLE_SSH_TARGET=ubuntu@141.147.62.244 \
TRAININGAI_ORACLE_SSH_KEY=/Users/giuseppe/pokoinpos/keys/peer3/ssh-key-2026-05-16.key \
TRAININGAI_ORACLE_REMOTE_DIR=/opt/trainingai-card-classifier \
TRAININGAI_ORACLE_PORT=17860 \
workflows/deploy-trainingai-oracle-classifier.sh
```

The deploy script uploads only `integrations/trainingai-oracle-api`, builds a
Docker image on the VM, and runs it bound to `127.0.0.1:17860`.

## Runtime Env On Oracle

Create `/opt/trainingai-card-classifier/.env` on the VM. Keep real values out of
git.

```text
TRAININGAI_DATA_DIR=/opt/trainingai-card-classifier/data
TRAININGAI_ASSET_BASE_URL=https://raw.githubusercontent.com/SabatinoRaffaella/PokemonCardRecognizer/main/main_app
TRAININGAI_IMAGE_BASE_URL=https://raw.githubusercontent.com/SabatinoRaffaella/PokemonCardRecognizer/main/main_app
TRAININGAI_MAX_UPLOAD_BYTES=8388608
TRAININGAI_MODEL_NAME=ViT-B-32
TRAININGAI_PRETRAINED=laion2b_s34b_b79k
# Optional Meilisearch OCR rerank (same marketplace index as api.pokoin.com).
# On peer3 Docker, point at the Meili SSH tunnel on the Docker bridge:
MEILI_HOST=http://172.17.0.1:27700
MEILI_API_KEY=<redacted>
MEILI_MARKETPLACE_INDEX=marketplace_cards
TRAININGAI_ENABLE_MEILI_RERANK=1
```

When OCR reads a name (for example `chien` + `pao`), the classifier queries
Meili for blueprint `card_id`s and injects matching TrainingAI vectors even if
CLIP ranked them outside the FAISS rerank pool. `GET /health` reports
`meili.configured`.

If Colab generated newer artifacts, upload them to:

```text
/opt/trainingai-card-classifier/data/pokemon.index
/opt/trainingai-card-classifier/data/metadata.json
/opt/trainingai-card-classifier/data/card_paths.json
```

If the files are absent, the service downloads the current artifacts from
`TRAININGAI_ASSET_BASE_URL` at startup.

## Reverse Proxy

Expose the local container through Caddy or Nginx on the VM. Example Caddy site:

```text
trainingai-api.pokoin.com {
  reverse_proxy 127.0.0.1:17860
}
```

Templates are available at:

- `deploy/trainingai-caddy.example`
- `deploy/trainingai-nginx.example.conf`

Then configure the public Worker:

```bash
wrangler secret put TRAININGAI_CLASSIFIER_URL --config wrangler.trainingai-cardvault-images.jsonc
workflows/deploy-trainingai-cardvault-images.sh
```

Use `https://trainingai-api.pokoin.com` as the secret value.

The same Worker can point to a Hugging Face Space instead:

```text
TRAININGAI_CLASSIFIER_URL=https://<user>-<space>.hf.space
```

`wrangler.trainingai-cardvault-images.jsonc` includes an hourly cron trigger
(`0 * * * *`). On each scheduled event the Worker sends a light `GET /health`
to `TRAININGAI_CLASSIFIER_URL`. This is enough for a gentle free-tier keep-alive
without making classification calls.

## Colab Artifact Handoff

After training or refreshing embeddings in Colab, download the three generated
files and upload them to the Oracle VM:

```bash
scp pokemon.index metadata.json card_paths.json \
  ubuntu@141.147.62.244:/opt/trainingai-card-classifier/data/
```

Then restart the classifier container:

```bash
ssh ubuntu@141.147.62.244 \
  'sudo docker restart pokoin-trainingai-card-classifier'
```

## Tests

```bash
curl -fsS https://trainingai-api.pokoin.com/health
curl -X POST https://trainingai-api.pokoin.com/classify \
  -F "image=@card.jpg" \
  -F "top_k=3"
curl -X POST https://trainingai.pokoin.com/api/classify \
  -F "image=@card.jpg" \
  -F "top_k=3"
```
