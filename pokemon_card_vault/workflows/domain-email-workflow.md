# Domain Email Workflow

Use this workflow when configuring `@pokoin.com` mailbox delivery, Zoho Mail,
Cloudflare Email Routing, transactional email, SPF, DKIM, DMARC, or BIMI.

## Current Roles

- Zoho Mail should own human inboxes such as `contact@pokoin.com` and
  `support@pokoin.com`.
- Resend should continue to send transactional app email such as
  `verify@pokoin.com`, `no-reply@pokoin.com`, and marketplace seller sale
  notifications from `market@pokoin.com`.
- Cloudflare DNS is the source of truth for `pokoin.com` mail records.
- Zoho and Cloudflare admin credentials are local operator secrets only. They
  are not required by the deployed Vercel app after DNS is configured.
- Cloudflare Email Routing was previously used for forwarding
  `contact@pokoin.com` to Gmail. Its managed MX records were unlocked and
  replaced with Zoho MX records on 2026-05-20.

## Existing Assets

- BIMI logo asset: `web/bimi.svg`
- Public BIMI URL: `https://pokoin.com/bimi.svg`
- BIMI DNS name: `default._bimi.pokoin.com`
- Zoho domain state found through the Mail Admin API:
  - `pokoin.com` is verified.
  - mail hosting is enabled.
  - organization ID is `20114760989`.
  - DKIM selector is `zmail`.
  - DKIM DNS host is `zmail._domainkey.pokoin.com`.
  - MX, SPF, and DKIM verification all pass in Zoho after the DNS cutover.
- Site contact references:
  - `web/index.html`
  - `lib/widgets/site_footer.dart`

## Values Needed From Zoho

Do not guess these values if Zoho shows different records in the admin console.
Ask the user to copy or screenshot the Zoho records.

1. Domain verification:
   - TXT name/host
   - TXT value
2. MX records:
   - host/name, priority, value for each Zoho MX row
   - Zoho EU commonly uses `mx.zoho.eu`, `mx2.zoho.eu`, and `mx3.zoho.eu`, but
     use the exact values shown by Zoho.
3. SPF:
   - TXT value shown by Zoho, usually containing `include:zohomail.eu`
4. DKIM:
   - selector/name, for example `<selector>._domainkey`
   - TXT value beginning with `v=DKIM1;`
5. Mailboxes and aliases:
   - `contact@pokoin.com`
   - any aliases such as `support@pokoin.com`, `admin@pokoin.com`, or
     `no-reply@pokoin.com`

## Automation Prerequisites

`ZOHO_CLIENTID` and `ZOHO_CLIENT_SECRET` can use Zoho EU client credentials for
domain-state reads and DNS verification calls. Store any longer-lived refresh
token only in `.env.local` if future mailbox/user automation needs it.

Required local-only values for Zoho API automation:

```bash
ZOHO_CLIENTID=
ZOHO_CLIENT_SECRET=
ZOHO_REFRESH_TOKEN=
ZOHO_ORG_ID=
```

For the current Zoho client, client-credentials access can read domain state.
It does not return a refresh token, but it was enough to retrieve the verified
domain, `ZOHO_ORG_ID`, and generated DKIM key. If longer-lived admin automation
is needed, generate `ZOHO_REFRESH_TOKEN` with a Self Client authorization code.

Use Zoho EU OAuth endpoints for this domain:

```text
https://accounts.zoho.eu/oauth/v2/auth
https://accounts.zoho.eu/oauth/v2/token
```

Useful scopes for domain/mailbox automation include:

```text
ZohoMail.organization.domains.ALL
ZohoMail.organization.accounts.ALL
```

Cloudflare automation requires DNS write permission, not only Wrangler Email
Routing permission. The current setup uses a Cloudflare Global API Key in
`.env.local`:

```bash
CLOUDFLARE_API_EMAIL=
CLOUDFLARE_GLOBAL_API_KEY=
```

Prefer a scoped token with Zone DNS Edit for `pokoin.com` for future work, but
the global key path is supported when a scoped token is not available.

Do not add Zoho admin credentials or Cloudflare DNS credentials to Vercel
production unless new server code explicitly needs to manage DNS/mail settings
at runtime. Current production runtime email variables are `RESEND_API_KEY`,
`EMAIL_FROM`, `NO_REPLY_EMAIL_FROM`, and `ADMIN_SIGNUP_EMAIL`. Marketplace
seller sale notifications also use `RESEND_API_KEY`, with a fixed sender of
`market@pokoin.com`; verify that sender/domain in Resend before enabling
production sends.

## Zoho SAML Screen Is Separate

The Zoho "Upload metadata" SAML screen is for single sign-on only. It is not
required for normal mailbox delivery and it does not configure MX, SPF, DKIM,
DMARC, or BIMI.

If SAML SSO is required later, use
`workflows/zoho-saml-idp-metadata-template.xml` as a placeholder template. A
real uploadable metadata file must come from the identity provider and needs:

- IdP entity ID
- login URL
- logout URL, if supported
- X.509 signing certificate

Do not invent these values. They must be copied from the chosen IdP, such as
Google Workspace, Microsoft Entra ID, Okta, Auth0, or Cloudflare Access.

## Recommended DNS Shape

Zoho owns inbound mail for `pokoin.com`.

```text
pokoin.com. MX 10 mx.zoho.eu.
pokoin.com. MX 20 mx2.zoho.eu.
pokoin.com. MX 50 mx3.zoho.eu.
```

SPF should include Zoho for mailbox sending. If Resend is still used for app
email, keep the Resend-approved records from the Resend domain setup too. Avoid
multiple root SPF records; merge all allowed senders into one TXT record.

```text
pokoin.com. TXT "v=spf1 include:zohomail.eu ~all"
```

DKIM must come from Zoho because the selector and public key are generated per
domain.

```text
zmail._domainkey.pokoin.com. TXT "v=DKIM1; k=rsa; p=..."
```

DMARC should stay at quarantine or stronger once SPF/DKIM pass:

```text
_dmarc.pokoin.com. TXT "v=DMARC1; p=quarantine; rua=mailto:pokoinpos@gmail.com"
```

BIMI can stay pointed at the hosted SVG:

```text
default._bimi.pokoin.com. TXT "v=BIMI1; l=https://pokoin.com/bimi.svg;"
```

## Cloudflare CLI Checks

Use Wrangler to verify account access:

```bash
wrangler whoami
wrangler email routing list
wrangler email routing rules list pokoin.com
wrangler email routing addresses list
```

Use DNS checks after every change:

```bash
dig +short MX pokoin.com
dig +short TXT pokoin.com
dig +short TXT zmail._domainkey.pokoin.com
dig +short TXT _dmarc.pokoin.com
dig +short TXT default._bimi.pokoin.com
```

Trigger Zoho verification after DNS changes:

```text
PUT https://mail.zoho.eu/api/organization/20114760989/domains/pokoin.com
{"mode":"verifyMxRecord"}
{"mode":"VerifySpfRecord"}
{"mode":"verifyDkimKey","dkimId":"<from dkimDetailList>"}
```

## Cutover Steps

1. Confirm the Zoho mailbox `contact@pokoin.com` exists.
2. Confirm Zoho domain verification is complete.
3. Add Zoho DKIM TXT in Cloudflare and verify DKIM in Zoho.
4. Replace Cloudflare Email Routing MX records with Zoho MX records.
5. Keep exactly one root SPF TXT record and merge all approved senders.
6. Keep or update DMARC.
7. Keep BIMI pointed to `https://pokoin.com/bimi.svg`.
8. Send test mail from an external address that is not the destination inbox.
9. In Zoho, send a reply to Gmail and confirm SPF/DKIM/DMARC pass in message
   headers.

Steps 2-7 were completed on 2026-05-20. Zoho API verification returned
`mxstatus: true`, `spfstatus: true`, and `dkimstatus: true`.

## Important Notes

- Do not delete working MX records until Zoho confirms the domain is ready and a
  mailbox exists, otherwise inbound email can bounce.
- Do not publish more than one SPF TXT record at `pokoin.com`.
- BIMI display in inboxes is optional and may require a stricter DMARC policy
  and, for some providers, a Verified Mark Certificate.
