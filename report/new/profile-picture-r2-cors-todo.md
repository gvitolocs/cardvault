# TODO: Fix R2 Profile Picture Browser Loading

## Problem

`nesaggezza` still did not see his profile picture even though the migrated R2
object returned `200 OK` from direct HTTP checks.

The checked R2 URL:

```text
https://pub-cefbe784076b42bcbb6d3b7c4f53b22c.r2.dev/profile-pictures/jZX1dJsfRAYsV7HHEcK3NdDSqI83/google-59ea97e803245d12bcaa.webp
```

returned:

```text
content-type: image/webp
content-length: 1556
access-control-allow-origin: <missing>
access-control-allow-methods: <missing>
```

Flutter web image loading can fail in the browser even when server-side `curl`
or `fetch` sees `200 OK`, because the public R2 endpoint does not currently send
CORS headers for `https://pokoin.com`.

## Temporary Repair

The Firestore profile for `nesaggezza`
(`jZX1dJsfRAYsV7HHEcK3NdDSqI83`) was restored to the Firebase Auth Google
`photoURL` and marked:

```text
photoSource = google-direct-temporary
```

## Real Fix Needed

- Serve profile pictures from a same-origin or properly CORS-enabled URL.
- Preferred options:
  - add a Cloudflare Worker or Vercel image proxy under `pokoin.com`;
  - configure R2/custom-domain CORS so browser image loads from `pokoin.com`
    succeed;
  - store a public custom-domain URL with correct response headers instead of
    `pub-*.r2.dev`.
- Update `assertPublicAvatarUrl` to check browser-relevant headers, not only
  `response.ok`.
- Re-run the guarded migration only after the browser-load check passes.
- Avoid overwriting users marked `google-direct-temporary` until the R2 URL path
  is confirmed usable from the web app.
