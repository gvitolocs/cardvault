# Forum Workflow

Use this workflow when changing `/forum`, forum APIs, Supabase forum tables, or
Cloudflare R2 forum media.

## Architecture

- Firebase Auth remains the canonical user identity.
- Firestore `users/{uid}` remains the canonical profile source for public author
  snapshots such as username/display name and avatar URL.
- Supabase stores forum categories, topics, replies, media metadata, and optional
  links to marketplace cards.
- Cloudflare R2 stores uploaded forum images. Supabase stores only object
  metadata and public URLs.
- Vercel APIs under `api/*.js` verify Firebase ID tokens before writes and use
  `SUPABASE_SERVICE_ROLE_KEY` for database writes.

## Required Environment

The app already needs the standard Firebase and Supabase variables documented in
`workflows/README.md`. Forum media additionally needs:

```bash
CLOUDFLARE_ACCOUNT_ID=
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_FORUM_MEDIA_BUCKET=pokoin-forum-media
R2_FORUM_MEDIA_PUBLIC_URL=https://<public-forum-media-origin>
```

The forum bucket should be public or exposed through a public custom domain/CDN.
Use object keys under `forum-media/{uid}/{uuid}.webp`.

## Database Changes

Forum schema lives in `supabase/migrations/20260518204500_forum.sql`.

After editing the schema:

```bash
supabase db push
```

The migration seeds the default categories:

- `general`
- `cards`
- `pkn`
- `validators`

Open forum rows are publicly readable through Supabase RLS. Writes are handled by
server-side APIs only.

## API Surface

- `GET /api/forum` returns categories and latest topics.
- `GET /api/forum?categoryId=cards` returns filtered topics.
- `GET /api/forum?topicId=<uuid>` returns one topic, replies, and media.
- `POST /api/forum-create-topic` creates a topic for the Firebase user.
- `POST /api/forum-create-post` creates a reply for the Firebase user.
- `POST /api/forum-upload-media` uploads an image to R2 and records metadata in
  Supabase.

When adding API files, update both `vercel.json` rewrites and
`deploy-pokoin-web.sh` so the files are copied into `build/web/api`.

## Verification

1. Run Dart analysis and tests:
   ```bash
   flutter analyze
   flutter test
   ```
2. Verify the API files are copied by the deploy script or inspect `build/web/api`
   after a local build.
3. Test anonymous reads:
   ```bash
   curl https://pokoin.com/api/forum
   ```
4. Test authenticated topic/reply/media flows from the browser with a signed-in
   Firebase user.
5. Deploy with the project workflow only:
   ```bash
   ./deploy-pokoin-web.sh
   ```
