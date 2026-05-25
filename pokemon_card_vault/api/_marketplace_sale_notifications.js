const { sendEmail } = require('./_email');

const DEFAULT_MARKETPLACE_FROM = 'market@pokoin.com';
const PAID_STATUSES = new Set(['paid', 'completed', 'fulfilled']);

function marketplaceEmailFrom() {
  return DEFAULT_MARKETPLACE_FROM;
}

function escapeHtml(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function cleanText(value, maxLength = 240) {
  return String(value || '').trim().slice(0, maxLength);
}

function canEmailUser(email) {
  const normalized = String(email || '').trim().toLowerCase();
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalized) &&
    !normalized.endsWith('@wallet.pokoin.local');
}

function numberValue(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function formatPkn(value) {
  const number = numberValue(value);
  if (Number.isInteger(number)) return `${number} PKN`;
  return `${Math.round(number * 100) / 100} PKN`;
}

function orderIsPaid(orderData = {}) {
  const paymentStatus = cleanText(orderData.paymentStatus, 40).toLowerCase();
  const status = cleanText(orderData.status, 40).toLowerCase();
  return PAID_STATUSES.has(paymentStatus) || PAID_STATUSES.has(status) || Boolean(orderData.paidAt);
}

function sellerUidForItem(item = {}) {
  return cleanText(item.sellerUid ?? item.seller_uid, 160);
}

function sellerNameForItem(item = {}) {
  return cleanText(item.sellerName ?? item.seller_name, 120) || 'Pokoin seller';
}

function cardNameForItem(item = {}) {
  const card = item.card && typeof item.card === 'object' ? item.card : {};
  return cleanText(item.cardName ?? item.card_name ?? card.name, 240) || 'Pokemon card';
}

function itemQuantity(item = {}) {
  const quantity = Number(item.quantity || 0);
  return Number.isSafeInteger(quantity) && quantity > 0 ? quantity : 1;
}

function itemUnitPrice(item = {}) {
  return numberValue(item.unitPricePkn ?? item.pricePkn ?? item.price_pkn, 0);
}

function itemTotalPrice(item = {}) {
  const explicit = numberValue(item.totalPricePkn ?? item.total_pkn, NaN);
  if (Number.isFinite(explicit) && explicit > 0) return explicit;
  return itemUnitPrice(item) * itemQuantity(item);
}

function groupOrderItemsBySeller(items = []) {
  const bySeller = new Map();
  for (const rawItem of items) {
    const item = rawItem && typeof rawItem === 'object' ? rawItem : {};
    const sellerUid = sellerUidForItem(item);
    if (!sellerUid) continue;
    const existing = bySeller.get(sellerUid) || {
      sellerUid,
      sellerName: sellerNameForItem(item),
      items: [],
      totalPkn: 0,
      quantity: 0,
    };
    const quantity = itemQuantity(item);
    const totalPkn = itemTotalPrice(item);
    existing.items.push(item);
    existing.totalPkn += totalPkn;
    existing.quantity += quantity;
    if (!existing.sellerName || existing.sellerName === 'Pokoin seller') {
      existing.sellerName = sellerNameForItem(item);
    }
    bySeller.set(sellerUid, existing);
  }
  return [...bySeller.values()];
}

function notificationMarkerId(orderId, sellerUid) {
  return `${encodeURIComponent(cleanText(orderId, 300))}__${encodeURIComponent(cleanText(sellerUid, 300))}`;
}

function itemDescription(item = {}) {
  const details = [
    cardNameForItem(item),
    cleanText(item.condition, 40),
    cleanText(item.language, 20),
    item.reverse === true ? 'Reverse' : '',
    item.graded === true
      ? [cleanText(item.gradingCompany, 80) || 'Graded', cleanText(item.grade, 40)]
          .filter(Boolean)
          .join(' ')
      : '',
  ].filter(Boolean);
  return details.join(' - ');
}

function buildSellerSaleEmail({ orderId, sellerGroup }) {
  const shortOrderId = cleanText(orderId, 80);
  const sellerName = sellerGroup.sellerName || 'Pokoin seller';
  const subject = `You sold ${sellerGroup.quantity} card${sellerGroup.quantity === 1 ? '' : 's'} on Pokoin`;
  const itemLines = sellerGroup.items.map((item) => {
    const quantity = itemQuantity(item);
    const unit = itemUnitPrice(item);
    const total = itemTotalPrice(item);
    return `- ${itemDescription(item)} x ${quantity} at ${formatPkn(unit)} each (${formatPkn(total)})`;
  });
  const notes = sellerGroup.items
    .map((item) => cleanText(item.buyerNotes, 500))
    .filter(Boolean);
  const uniqueNotes = [...new Set(notes)];
  const text = [
    `Hi ${sellerName},`,
    '',
    `Your card${sellerGroup.quantity === 1 ? ' has' : 's have'} sold and the order is paid.`,
    '',
    `Order: ${shortOrderId}`,
    `Seller payout credited: ${formatPkn(sellerGroup.totalPkn)}`,
    '',
    'Sold cards:',
    ...itemLines,
    ...(uniqueNotes.length
      ? ['', 'Buyer notes:', ...uniqueNotes.map((note) => `- ${note}`)]
      : []),
    '',
    'Next steps: open your Pokoin seller orders, confirm fulfillment, and prepare shipping if the listing included shipping.',
  ].join('\n');
  const htmlItems = sellerGroup.items.map((item) => `
    <li>
      <strong>${escapeHtml(itemDescription(item))}</strong><br>
      Qty ${itemQuantity(item)} at ${escapeHtml(formatPkn(itemUnitPrice(item)))} each
      (${escapeHtml(formatPkn(itemTotalPrice(item)))})
    </li>
  `).join('');
  const htmlNotes = uniqueNotes.length
    ? `<h2 style="font-size:16px;margin:20px 0 8px">Buyer notes</h2><ul>${uniqueNotes.map((note) => `<li>${escapeHtml(note)}</li>`).join('')}</ul>`
    : '';
  const html = `
    <div style="font-family:Inter,Arial,sans-serif;line-height:1.6;color:#0f172a">
      <h1 style="margin:0 0 16px">You made a sale on Pokoin</h1>
      <p>Hi ${escapeHtml(sellerName)},</p>
      <p>Your card${sellerGroup.quantity === 1 ? ' has' : 's have'} sold and the order is paid.</p>
      <p><strong>Order:</strong> ${escapeHtml(shortOrderId)}<br>
      <strong>Seller payout credited:</strong> ${escapeHtml(formatPkn(sellerGroup.totalPkn))}</p>
      <h2 style="font-size:16px;margin:20px 0 8px">Sold cards</h2>
      <ul>${htmlItems}</ul>
      ${htmlNotes}
      <p style="margin-top:20px">Next steps: open your Pokoin seller orders, confirm fulfillment, and prepare shipping if the listing included shipping.</p>
      <p style="color:#64748b;font-size:14px">Buyer private contact details are not included in this notification.</p>
    </div>
  `;
  return { subject, text, html };
}

async function lookupSellerEmail({ admin, firestore, sellerUid }) {
  const userDoc = await firestore.collection('users').doc(sellerUid).get().catch(() => null);
  const profile = userDoc?.data?.() || {};
  const profileEmail = cleanText(profile.email, 320).toLowerCase();
  if (canEmailUser(profileEmail)) {
    return {
      email: profileEmail,
      username: cleanText(profile.username || profile.displayName, 120),
    };
  }
  const authUser = await admin.auth().getUser(sellerUid).catch(() => null);
  const authEmail = cleanText(authUser?.email, 320).toLowerCase();
  return {
    email: canEmailUser(authEmail) ? authEmail : '',
    username: cleanText(profile.username || profile.displayName || authUser?.displayName, 120),
  };
}

async function claimNotificationMarker({ admin, firestore, orderId, sellerUid, sellerGroup, email }) {
  const markerRef = firestore
    .collection('order_seller_sale_notifications')
    .doc(notificationMarkerId(orderId, sellerUid));
  let claimed = false;
  await firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(markerRef);
    if (existing.exists) return;
    transaction.set(markerRef, {
      orderId,
      sellerUid,
      sellerEmail: email || '',
      itemCount: sellerGroup.items.length,
      quantity: sellerGroup.quantity,
      totalPkn: sellerGroup.totalPkn,
      status: 'claimed',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    claimed = true;
  });
  return { claimed, markerRef };
}

async function markNotification(markerRef, admin, payload) {
  if (!markerRef?.set) return;
  await markerRef.set(
    {
      ...payload,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function sendSellerSaleNotificationsForPaidOrder({
  admin,
  firestore,
  orderId,
  orderData,
  sendEmailFn = sendEmail,
  lookupSellerFn = lookupSellerEmail,
  claimNotificationFn = claimNotificationMarker,
  markNotificationFn = markNotification,
  logger = console,
}) {
  if (!orderId || !orderIsPaid(orderData)) {
    return { ok: true, skipped: true, reason: 'Order is not paid.' };
  }
  const sellerGroups = groupOrderItemsBySeller(orderData.items || []);
  const results = [];
  for (const sellerGroup of sellerGroups) {
    const sellerUid = sellerGroup.sellerUid;
    let markerRef = null;
    try {
      const seller = await lookupSellerFn({ admin, firestore, sellerUid, sellerGroup });
      const email = cleanText(seller?.email, 320).toLowerCase();
      const claim = await claimNotificationFn({
        admin,
        firestore,
        orderId,
        sellerUid,
        sellerGroup,
        email,
      });
      markerRef = claim.markerRef || null;
      if (!claim.claimed) {
        results.push({ sellerUid, ok: true, skipped: true, reason: 'Notification already claimed.' });
        continue;
      }
      if (!canEmailUser(email)) {
        await markNotificationFn(markerRef, admin, {
          status: 'skipped',
          reason: 'Seller has no deliverable email.',
        });
        results.push({ sellerUid, ok: true, skipped: true, reason: 'Seller has no deliverable email.' });
        continue;
      }
      const message = buildSellerSaleEmail({
        orderId,
        sellerGroup: {
          ...sellerGroup,
          sellerName: sellerGroup.sellerName || seller?.username || 'Pokoin seller',
        },
      });
      const delivery = await sendEmailFn({
        from: marketplaceEmailFrom(),
        to: email,
        subject: message.subject,
        text: message.text,
        html: message.html,
      });
      await markNotificationFn(markerRef, admin, {
        status: delivery?.skipped ? 'skipped' : 'sent',
        reason: delivery?.reason || null,
        deliveryId: delivery?.id || null,
        sentAt: delivery?.skipped ? null : admin.firestore.FieldValue.serverTimestamp(),
      });
      results.push({ sellerUid, ok: true, ...delivery });
    } catch (error) {
      logger.error?.('seller sale notification failed', {
        orderId,
        sellerUid,
        error: error.message || String(error),
      });
      await markNotificationFn(markerRef, admin, {
        status: 'failed',
        error: error.message || String(error),
      }).catch(() => {});
      results.push({
        sellerUid,
        ok: false,
        error: error.message || 'Seller sale notification failed.',
      });
    }
  }
  return { ok: true, sellerNotifications: results };
}

module.exports = {
  buildSellerSaleEmail,
  canEmailUser,
  groupOrderItemsBySeller,
  marketplaceEmailFrom,
  notificationMarkerId,
  orderIsPaid,
  sendSellerSaleNotificationsForPaidOrder,
};
