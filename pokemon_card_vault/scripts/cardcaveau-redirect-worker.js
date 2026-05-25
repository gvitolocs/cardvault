const SECURITY_HEADERS = {
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "X-Robots-Tag": "noai, noimageai",
};

const SECURITY_TXT = `Contact: mailto:contact@pokoin.com
Preferred-Languages: en, it
Canonical: https://cardcaveau.com/.well-known/security.txt
Policy: https://pokoin.com/
`;

function withSecurityHeaders(response) {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(SECURITY_HEADERS)) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/.well-known/security.txt" || url.pathname === "/security.txt") {
      return withSecurityHeaders(new Response(SECURITY_TXT, {
        headers: {
          "Content-Type": "text/plain; charset=utf-8",
          "Cache-Control": "public, max-age=3600",
        },
      }));
    }

    url.protocol = "https:";
    url.hostname = "pokoin.com";
    return withSecurityHeaders(Response.redirect(url.toString(), 301));
  },
};
