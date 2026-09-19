// One-time (re-runnable) grandfathering backfill for the email/password
// verification rollout.
//
// Legacy web email/password users were created client-side before the
// verify-first flow existed, so some have email_verified=false. They are
// already active Pokoin users under the old semantics, so instead of locking
// them out we stamp a pok_email_verified custom claim on every password
// provider user that is not verified yet. The bearer guard in
// api/_firebase.js only rejects password tokens that have neither
// email_verified nor pok_email_verified, so after this script runs it is safe
// to set POKOIN_REQUIRE_VERIFIED_PASSWORD=1.
//
// Dry-run by default. Apply with --apply.
//
//   node scripts/backfill-password-email-verification.js           # dry run
//   node scripts/backfill-password-email-verification.js --apply   # write claims
//
// Env: FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY.

const admin = require('firebase-admin');

// Password-identities created through the verify-first flow are born verified;
// everything else with a password provider is a legacy user to grandfather.
function needsBackfillClaim(userRecord) {
  const providers = (userRecord?.providerData || []).map((entry) => entry?.providerId);
  return providers.includes('password') && userRecord?.emailVerified !== true;
}

async function main() {
  const apply = process.argv.includes('--apply');
  const serviceAccount = {
    projectId: process.env.FIREBASE_PROJECT_ID,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
  };
  if (!serviceAccount.projectId || !serviceAccount.clientEmail || !serviceAccount.privateKey) {
    console.error('FIREBASE_PROJECT_ID / FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY are required.');
    process.exitCode = 1;
    return;
  }

  if (!admin.apps.length) {
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  }
  const auth = admin.auth();

  let scanned = 0;
  let claimed = 0;
  let nextPageToken;
  do {
    const page = await auth.listUsers(1000, nextPageToken);
    for (const userRecord of page.users) {
      scanned += 1;
      if (!needsBackfillClaim(userRecord)) {
        continue;
      }
      claimed += 1;
      const current = userRecord.customClaims || {};
      if (current.pok_email_verified === true) {
        claimed -= 1;
        continue;
      }
      if (apply) {
        await auth.setCustomUserClaims(userRecord.uid, {
          ...current,
          pok_email_verified: true,
        });
        console.log(`claimed ${userRecord.uid} ${userRecord.email || ''}`);
      } else {
        console.log(`would claim ${userRecord.uid} ${userRecord.email || ''}`);
      }
    }
    nextPageToken = page.pageToken;
  } while (nextPageToken);

  console.log(`scanned ${scanned} users, ${claimed} password users need the pok_email_verified claim${apply ? '' : ' (dry run)'}`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error('backfill failed', error);
    process.exitCode = 1;
  });
}

module.exports = { needsBackfillClaim };
