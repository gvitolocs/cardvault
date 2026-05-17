const DEFAULT_FROM = 'Pokoin <verify@pokoin.com>';
const DEFAULT_NO_REPLY_FROM = 'Pokoin <no-reply@pokoin.com>';
const DEFAULT_ADMIN_TO = 'pokoinpos@gmail.com';

function emailFrom() {
  return process.env.EMAIL_FROM || DEFAULT_FROM;
}

function noReplyEmailFrom() {
  return process.env.NO_REPLY_EMAIL_FROM || DEFAULT_NO_REPLY_FROM;
}

function siteUrl() {
  return process.env.PUBLIC_SITE_URL || 'https://pokoin.com';
}

function escapeHtml(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function canEmailUser(email) {
  const normalized = String(email || '').trim().toLowerCase();
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalized) &&
    !normalized.endsWith('@wallet.pokoin.local');
}

async function sendEmail({ to, subject, html, text, from }) {
  const apiKey = process.env.RESEND_API_KEY || '';
  if (!apiKey) {
    return { ok: false, skipped: true, reason: 'RESEND_API_KEY is not configured.' };
  }

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: from || emailFrom(),
      to,
      subject,
      html,
      text,
    }),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw Object.assign(
      new Error(payload.message || payload.error || 'Email delivery failed.'),
      { statusCode: 502 },
    );
  }

  return { ok: true, id: payload.id || null };
}

async function sendVerificationEmail({ admin, email, username, verificationLink }) {
  const link = verificationLink || await admin.auth().generateEmailVerificationLink(email, {
    url: `${siteUrl()}/auth?verified=1`,
    handleCodeInApp: false,
  });
  const safeUsername = String(username || 'Pokoin user');

  return sendEmail({
    from: emailFrom(),
    to: email,
    subject: 'Verify your Pokoin account',
    text: [
      `Hi ${safeUsername},`,
      '',
      'Verify your Pokoin account with this link:',
      link,
      '',
      'If you did not create a Pokoin account, you can ignore this email.',
    ].join('\n'),
    html: `
      <div style="font-family:Inter,Arial,sans-serif;line-height:1.6;color:#0f172a">
        <h1 style="margin:0 0 16px">Verify your Pokoin account</h1>
        <p>Hi ${safeUsername},</p>
        <p>Click the button below to verify your email address for Pokoin.</p>
        <p>
          <a href="${link}" style="display:inline-block;background:#facc15;color:#111827;padding:12px 18px;border-radius:12px;text-decoration:none;font-weight:700">
            Verify email
          </a>
        </p>
        <p style="color:#64748b;font-size:14px">If the button does not work, open this link:<br>${link}</p>
        <p style="color:#64748b;font-size:14px">If you did not create a Pokoin account, you can ignore this email.</p>
      </div>
    `,
  });
}

async function sendPknReceivedEmail({
  email,
  username = '',
  amountPkn,
  senderUsername = '',
}) {
  if (!canEmailUser(email)) {
    return { ok: true, skipped: true, reason: 'Recipient has no deliverable email.' };
  }
  const amount = Number(amountPkn);
  if (!Number.isFinite(amount) || amount <= 0) {
    return { ok: true, skipped: true, reason: 'Invalid received amount.' };
  }
  const safeUsername = escapeHtml(username || 'Pokoin user');
  const safeSender = escapeHtml(senderUsername || 'another Pokoin user');
  const safeAmount = Number.isInteger(amount) ? String(amount) : String(amount);
  const walletLink = `${siteUrl()}/wallet`;

  return sendEmail({
    from: noReplyEmailFrom(),
    to: email,
    subject: `You have received ${safeAmount} PKN`,
    text: [
      `Hi ${username || 'Pokoin user'},`,
      '',
      `You have received ${safeAmount} PKN from ${senderUsername || 'another Pokoin user'}.`,
      '',
      `Open your wallet: ${walletLink}`,
    ].join('\n'),
    html: `
      <div style="font-family:Inter,Arial,sans-serif;line-height:1.6;color:#0f172a">
        <h1 style="margin:0 0 16px">You have received ${safeAmount} PKN</h1>
        <p>Hi ${safeUsername},</p>
        <p>You have received <strong>${safeAmount} PKN</strong> from ${safeSender}.</p>
        <p>
          <a href="${walletLink}" style="display:inline-block;background:#facc15;color:#111827;padding:12px 18px;border-radius:12px;text-decoration:none;font-weight:700">
            Open wallet
          </a>
        </p>
      </div>
    `,
  });
}

async function sendWelcomeEmail({
  email,
  username = '',
}) {
  if (!canEmailUser(email)) {
    return { ok: true, skipped: true, reason: 'User has no deliverable email.' };
  }
  const safeUsername = escapeHtml(username || 'Pokoin user');
  const docsLink = `${siteUrl()}/docs`;
  const projectLink = siteUrl();

  return sendEmail({
    from: noReplyEmailFrom(),
    to: email,
    subject: 'Welcome on board!',
    text: [
      'Welcome on board!',
      '',
      `Hi ${username || 'Pokoin user'},`,
      '',
      'Your Pokoin account is verified and ready.',
      'Read the documentation to understand the project, wallets, validators, and how PKN works:',
      docsLink,
      '',
      'We are happy to have you as part of the Pokoin project.',
      projectLink,
    ].join('\n'),
    html: `
      <div style="font-family:Inter,Arial,sans-serif;line-height:1.6;color:#0f172a">
        <h1 style="margin:0 0 16px">Welcome on board!</h1>
        <p>Hi ${safeUsername},</p>
        <p>Your Pokoin account is verified and ready.</p>
        <p>Read the documentation to understand the project, wallets, validators, and how PKN works.</p>
        <p>
          <a href="${docsLink}" style="display:inline-block;background:#facc15;color:#111827;padding:12px 18px;border-radius:12px;text-decoration:none;font-weight:700">
            Read documentation
          </a>
        </p>
        <p>We are happy to have you as part of the Pokoin project.</p>
      </div>
    `,
  });
}

function adminSignupEmail() {
  return process.env.ADMIN_SIGNUP_EMAIL || DEFAULT_ADMIN_TO;
}

async function sendSignupNotificationOnce({
  admin,
  firestore,
  uid,
  provider,
  email = '',
  username = '',
  walletAddress = '',
  emailVerified = false,
}) {
  const userRef = firestore.collection('users').doc(uid);
  const userDoc = await userRef.get();
  if (userDoc.data()?.signupNotificationSentAt) {
    return { ok: true, skipped: true, reason: 'Signup notification already sent.' };
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const safeProvider = String(provider || 'unknown');
  const safeEmail = String(email || userDoc.data()?.email || '');
  const safeUsername = String(username || userDoc.data()?.username || '');
  const safeWallet = String(walletAddress || userDoc.data()?.walletAddress || '');
  const verifiedText = emailVerified ? 'verified' : 'not verified';

  const delivery = await sendEmail({
    from: noReplyEmailFrom(),
    to: adminSignupEmail(),
    subject: `New Pokoin signup: ${safeUsername || safeEmail || uid}`,
    text: [
      'A new Pokoin account signed up successfully.',
      '',
      `Provider: ${safeProvider}`,
      `UID: ${uid}`,
      `Username: ${safeUsername || '-'}`,
      `Email: ${safeEmail || '-'}`,
      `Email status: ${verifiedText}`,
      `Wallet: ${safeWallet || '-'}`,
      '',
      `Time: ${new Date().toISOString()}`,
    ].join('\n'),
    html: `
      <div style="font-family:Inter,Arial,sans-serif;line-height:1.6;color:#0f172a">
        <h1 style="margin:0 0 16px">New Pokoin signup</h1>
        <p>A new Pokoin account signed up successfully.</p>
        <ul>
          <li><strong>Provider:</strong> ${safeProvider}</li>
          <li><strong>UID:</strong> ${uid}</li>
          <li><strong>Username:</strong> ${safeUsername || '-'}</li>
          <li><strong>Email:</strong> ${safeEmail || '-'}</li>
          <li><strong>Email status:</strong> ${verifiedText}</li>
          <li><strong>Wallet:</strong> ${safeWallet || '-'}</li>
        </ul>
        <p style="color:#64748b;font-size:14px">Time: ${new Date().toISOString()}</p>
      </div>
    `,
  });

  await userRef.set(
    {
      signupNotificationSentAt: now,
      signupNotificationProvider: safeProvider,
    },
    { merge: true },
  );
  return delivery;
}

module.exports = {
  sendEmail,
  sendPknReceivedEmail,
  sendSignupNotificationOnce,
  sendVerificationEmail,
  sendWelcomeEmail,
};
