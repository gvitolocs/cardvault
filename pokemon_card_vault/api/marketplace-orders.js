const { getFirebaseAdmin, verifyBearerToken } = require('./_firebase');
const { marketplaceQuery } = require('./_marketplace_db');
const { sendSellerSaleNotificationsForPaidOrder } = require('./_marketplace_sale_notifications');
const {
  addProductToCart,
  fetchCart,
  purchaseCart,
} = require('./_cardtrader_client');
const {
  _test: {
    readLiveCardTraderListings,
  },
} = require('./cardtrader-live-listings');

function cleanText(value, maxLength = 240) {
  return String(value || '').trim().slice(0, maxLength);
}

function cleanExternalListingId(value) {
  const text = cleanText(value, 160);
  return /^[A-Za-z0-9:_-]{3,160}$/.test(text) ? text : '';
}

function cleanOrderId(value) {
  const text = cleanText(value, 160);
  return /^[A-Za-z0-9_-]{6,160}$/.test(text) ? text : '';
}

function numberValue(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function timestampToIso(value) {
  return value?.toDate?.().toISOString?.() || null;
}

function orderPayload(orderId, data) {
  return {
    id: orderId,
    uid: data.uid || data.buyerUid || '',
    buyerUid: data.buyerUid || data.uid || '',
    items: Array.isArray(data.items) ? data.items : [],
    subtotalPkn: numberValue(data.subtotalPkn),
    taxPkn: numberValue(data.taxPkn),
    shippingPkn: numberValue(data.shippingPkn),
    totalPkn: numberValue(data.totalPkn),
    status: data.status || 'pending',
    paymentStatus: data.paymentStatus || 'pending',
    fulfillmentStatus: data.fulfillmentStatus || 'pending',
    fulfillmentMode: data.fulfillmentMode || 'physical',
    sellerUids: Array.isArray(data.sellerUids) ? data.sellerUids : [],
    createdAt: timestampToIso(data.createdAt),
    updatedAt: timestampToIso(data.updatedAt),
    paidAt: timestampToIso(data.paidAt),
  };
}

function itemListingId(item = {}) {
  return cleanText(item.listingId ?? item.listing_id, 80);
}

function itemQuantity(item = {}) {
  const quantity = Number(item.quantity || 0);
  return Number.isSafeInteger(quantity) && quantity > 0 ? quantity : 0;
}

function itemSellerUid(item = {}) {
  return cleanText(item.sellerUid ?? item.seller_uid, 160);
}

function itemTotalPkn(item = {}) {
  const explicit = numberValue(item.totalPricePkn ?? item.total_pkn, NaN);
  if (Number.isFinite(explicit) && explicit > 0) return explicit;
  return numberValue(item.unitPricePkn ?? item.pricePkn ?? item.price_pkn) * itemQuantity(item);
}

function cleanFulfillmentMode(value) {
  return cleanText(value, 40) === 'nft_only' ? 'nft_only' : 'physical';
}

function normalizeItem(item = {}) {
  const raw = item && typeof item === 'object' ? item : {};
  const card = raw.card && typeof raw.card === 'object' ? raw.card : {};
  const listingId = itemListingId(raw);
  const quantity = itemQuantity(raw);
  const unitPricePkn = numberValue(raw.unitPricePkn ?? raw.pricePkn ?? raw.price_pkn);
  return {
    card: {
      ...card,
      id: cleanText(card.id || raw.cardId || raw.card_id, 120),
      name: cleanText(card.name || raw.cardName || raw.card_name, 240),
    },
    quantity,
    listingId,
    sellerUid: itemSellerUid(raw),
    sellerName: cleanText(raw.sellerName ?? raw.seller_name, 120),
    condition: cleanText(raw.condition, 40),
    language: cleanText(raw.language, 20),
    unitPricePkn,
    totalPricePkn: itemTotalPkn({ ...raw, quantity, unitPricePkn }),
    reverse: raw.reverse === true,
    sealed: raw.sealed === true,
    graded: raw.graded === true,
    gradingCompany: cleanText(raw.gradingCompany, 80),
    grade: cleanText(raw.grade, 40),
    certificationId: cleanText(raw.certificationId, 120),
    shippingAvailable: raw.shippingAvailable === true,
    reserveAvailable: raw.reserveAvailable === true,
    nftAvailable: raw.nftAvailable === true,
    fulfillmentMode: cleanFulfillmentMode(raw.fulfillmentMode),
    buyerNotes: cleanText(raw.buyerNotes, 500),
    source: cleanText(raw.source, 80),
    sourceListingId: cleanText(raw.sourceListingId ?? raw.source_listing_id, 160),
    sourceMetadata: raw.sourceMetadata && typeof raw.sourceMetadata === 'object'
      ? raw.sourceMetadata
      : {},
  };
}

function normalizedItems(items) {
  if (!Array.isArray(items)) return [];
  return items.map(normalizeItem).filter((item) =>
    item.listingId &&
    item.sellerUid &&
    item.quantity > 0 &&
    item.unitPricePkn > 0);
}

function uniqueSellerUids(items) {
  return [...new Set(items.map((item) => item.sellerUid).filter(Boolean))];
}

function collectionPayloadForItem({ uid, item, orderId, now }) {
  const card = item.card || {};
  return {
    uid,
    cardId: cleanText(card.id, 120),
    blueprintId: cleanText(card.id, 120),
    quantity: item.quantity,
    condition: item.condition || 'NM',
    language: item.language || 'EN',
    firstEdition: false,
    holo: card.isHolo === true || card.isFoil === true,
    reverse: item.reverse === true,
    graded: item.graded === true,
    gradingCompany: item.gradingCompany || null,
    grade: item.grade || null,
    certificationId: item.certificationId || null,
    cardName: cleanText(card.name || item.cardName, 240),
    cardImageUrl: cleanText(card.imageUrl || card.previewImageUrl || item.cardImageUrl, 800),
    setName: cleanText(card.set || item.setName, 240),
    collectorNumber: cleanText(card.number || item.collectorNumber, 80),
    ownershipType: 'nft',
    nftStatus: 'owned',
    fulfillmentMode: 'nft_only',
    physicalShippingStatus: 'not_requested',
    sourceOrderId: orderId,
    sourceListingId: item.listingId,
    source: cleanText(item.source, 80),
    createdAt: now,
    updatedAt: now,
  };
}

function shippingAddressFromBody(value = {}) {
  const raw = value && typeof value === 'object' ? value : {};
  return {
    name: cleanText(raw.name, 120),
    line1: cleanText(raw.line1, 180),
    line2: cleanText(raw.line2, 180),
    city: cleanText(raw.city, 120),
    region: cleanText(raw.region, 120),
    postalCode: cleanText(raw.postalCode || raw.postal_code, 40),
    country: cleanText(raw.country, 80),
    phone: cleanText(raw.phone, 80),
  };
}

function validateShippingAddress(address) {
  if (!address.name || !address.line1 || !address.city || !address.postalCode || !address.country) {
    const error = new Error('Shipping address requires name, line1, city, postal code, and country.');
    error.statusCode = 400;
    throw error;
  }
}

function requestPayload(id, data) {
  return {
    id,
    uid: data.uid || '',
    collectionItemId: data.collectionItemId || '',
    status: data.status || 'pending_ops_review',
    chargeStatus: data.chargeStatus || 'not_charged',
    createdAt: timestampToIso(data.createdAt),
    updatedAt: timestampToIso(data.updatedAt),
  };
}

function isCardTraderLiveItem(item = {}) {
  const source = cleanText(item.source, 80).toLowerCase();
  const sourceListingId = cleanText(item.sourceListingId, 160).toLowerCase();
  return source === 'cardtrader_live' || sourceListingId.startsWith('cardtrader:live:');
}

function cardTraderProductIdForItem(item = {}) {
  const metadata = item.sourceMetadata && typeof item.sourceMetadata === 'object' ? item.sourceMetadata : {};
  const fromMetadata = cleanExternalListingId(
    metadata.cardtraderProductId || metadata.externalProductId || metadata.externalListingId,
  );
  if (fromMetadata) return fromMetadata;
  const match = cleanText(item.sourceListingId, 160).match(/^cardtrader:live:([A-Za-z0-9_-]+)$/i);
  return match ? cleanExternalListingId(match[1]) : '';
}

function configuredCardTraderBuyToken(env = process.env) {
  return cleanText(
    env.CARDTRADER_AUTH_TOKEN ||
      env.CARDTRADER_BUY_API_TOKEN ||
      env.CARDTRADER_PURCHASE_API_TOKEN ||
      env.CARDTRADER_API_TOKEN ||
      '',
    500,
  );
}

function cardTraderBuyEnabled(env = process.env) {
  return String(env.CARDTRADER_BUY_ENABLED || '').trim().toLowerCase() === 'true';
}

function cardTraderDryRun(env = process.env) {
  return String(env.CARDTRADER_BUY_DRY_RUN || '').trim().toLowerCase() === 'true' ||
    !cardTraderBuyEnabled(env);
}

function assertCardTraderBuyConfigured(env = process.env) {
  if (!cardTraderBuyEnabled(env)) {
    const error = new Error('CardTrader live buying is disabled.');
    error.statusCode = 503;
    error.code = 'CARDTRADER_BUY_DISABLED';
    throw error;
  }
  const token = configuredCardTraderBuyToken(env);
  if (!token) {
    const error = new Error('CardTrader buy token is not configured.');
    error.statusCode = 503;
    error.code = 'CARDTRADER_BUY_TOKEN_MISSING';
    throw error;
  }
  return token;
}

function cardTraderCartItems(cart = {}) {
  if (Array.isArray(cart)) return cart;
  if (!cart || typeof cart !== 'object') return [];
  for (const key of ['order_items', 'orderItems', 'items', 'products', 'cart_items']) {
    if (Array.isArray(cart[key])) return cart[key];
  }
  if (cart.cart && typeof cart.cart === 'object') {
    return cardTraderCartItems(cart.cart);
  }
  return [];
}

async function assertCardTraderCartIsEmpty(token, { getCart = fetchCart } = {}) {
  const cart = await getCart(token);
  const items = cardTraderCartItems(cart);
  if (items.length > 0) {
    const error = new Error('CardTrader cart is not empty; refusing automatic purchase.');
    error.statusCode = 409;
    error.code = 'CARDTRADER_CART_NOT_EMPTY';
    throw error;
  }
}

function assertCardTraderCheckoutCanProceed(items, body = {}, env = process.env) {
  if (!items.some(isCardTraderLiveItem)) return;
  if (body.cardTraderDryRun === true) return;
  if (cleanFulfillmentMode(body.fulfillmentMode) === 'nft_only') return;
  assertCardTraderBuyConfigured(env);
}

async function verifyCardTraderLiveItems(items, { query = marketplaceQuery } = {}) {
  const cardTraderItems = items.filter(isCardTraderLiveItem);
  for (const item of cardTraderItems) {
    const productId = cardTraderProductIdForItem(item);
    const blueprintId = cleanText(item.sourceMetadata?.cardtraderBlueprintId || item.card?.id, 80);
    if (!productId || !blueprintId) {
      const error = new Error('CardTrader listing metadata is incomplete.');
      error.statusCode = 409;
      throw error;
    }
    const payload = await readLiveCardTraderListings(
      {
        blueprintId,
        cardId: '',
        requestedId: blueprintId,
        requestedParam: 'blueprintId',
        language: '',
        limit: null,
      },
      { query },
    );
    const liveListing = (payload.listings || []).find((listing) =>
      cleanText(listing.cardtraderProductId || listing.externalProductId || listing.externalListingId, 160) === productId);
    if (!liveListing || Number(liveListing.quantity || 0) < item.quantity) {
      const error = new Error(`CardTrader listing ${productId} is no longer available.`);
      error.statusCode = 409;
      throw error;
    }
  }
}

async function markCardTraderPurchaseStatus({
  admin,
  firestore,
  orderId,
  item,
  status,
  payload = {},
}) {
  const productId = cardTraderProductIdForItem(item);
  if (!orderId || !productId) return;
  await firestore
    .collection('cardtrader_purchase_markers')
    .doc(`${orderId}__${productId}`)
    .set(
      {
        orderId,
        productId,
        listingId: item.listingId,
        quantity: item.quantity,
        status,
        ...payload,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

async function buyCardTraderItemsForPaidOrder({
  admin,
  firestore,
  orderId,
  orderData,
  env = process.env,
  addToCart = addProductToCart,
  buyCart = purchaseCart,
  getCart = fetchCart,
}) {
  const items = (orderData.items || []).filter(isCardTraderLiveItem);
  if (items.length === 0) {
    return { ok: true, skipped: true, reason: 'No CardTrader live items.' };
  }

  if (cardTraderDryRun(env)) {
    for (const item of items) {
      await markCardTraderPurchaseStatus({
        admin,
        firestore,
        orderId,
        item,
        status: 'dry_run',
        payload: {
          dryRun: true,
          reason: 'CARDTRADER_BUY_ENABLED is not true.',
        },
      });
    }
    return {
      ok: true,
      dryRun: true,
      attempted: 0,
      items: items.map((item) => ({
        productId: cardTraderProductIdForItem(item),
        quantity: item.quantity,
        status: 'dry_run',
      })),
    };
  }

  const token = assertCardTraderBuyConfigured(env);
  const results = [];
  for (const item of items) {
    const productId = cardTraderProductIdForItem(item);
    const markerRef = firestore.collection('cardtrader_purchase_markers').doc(`${orderId}__${productId}`);
    let claimed = false;
    await firestore.runTransaction(async (transaction) => {
      const existing = await transaction.get(markerRef);
      const status = cleanText(existing.data?.()?.status, 40);
      if (existing.exists && ['purchased', 'cart_added', 'claimed'].includes(status)) {
        return;
      }
      transaction.set(markerRef, {
        orderId,
        productId,
        listingId: item.listingId,
        quantity: item.quantity,
        status: 'claimed',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      claimed = true;
    });
    if (!claimed) {
      results.push({ productId, quantity: item.quantity, skipped: true, reason: 'Purchase already claimed.' });
      continue;
    }

    try {
      await assertCardTraderCartIsEmpty(token, { getCart });
      const viaCardTraderZero = item.sourceMetadata?.shippingMode === 'zero';
      const cartPayload = {
        product_id: Number(productId),
        quantity: item.quantity,
        via_cardtrader_zero: viaCardTraderZero,
      };
      await addToCart(token, cartPayload);
      await markCardTraderPurchaseStatus({
        admin,
        firestore,
        orderId,
        item,
        status: 'cart_added',
        payload: { viaCardTraderZero },
      });
      const purchase = await buyCart(token);
      await markCardTraderPurchaseStatus({
        admin,
        firestore,
        orderId,
        item,
        status: 'purchased',
        payload: {
          purchasedAt: admin.firestore.FieldValue.serverTimestamp(),
          cardtraderOrderId: cleanText(purchase?.id || purchase?.order_id || purchase?.uuid, 160),
        },
      });
      results.push({
        productId,
        quantity: item.quantity,
        ok: true,
        status: 'purchased',
      });
    } catch (error) {
      const purchaseStatus = error.code === 'CARDTRADER_CART_NOT_EMPTY'
        ? 'blocked_non_empty_cart'
        : 'failed';
      await markCardTraderPurchaseStatus({
        admin,
        firestore,
        orderId,
        item,
        status: purchaseStatus,
        payload: {
          error: error.message || 'CardTrader purchase failed.',
        },
      }).catch(() => {});
      results.push({
        productId,
        quantity: item.quantity,
        ok: false,
        error: error.message || 'CardTrader purchase failed.',
      });
    }
  }
  return { ok: results.every((result) => result.ok || result.skipped), dryRun: false, items: results };
}

async function verifyAndDecrementListings(items) {
  const decremented = [];
  try {
    for (const item of items) {
      if (isCardTraderLiveItem(item)) {
        decremented.push({
          listingId: item.listingId,
          quantity: item.quantity,
          cardId: item.card.id,
          external: true,
        });
        continue;
      }
      const result = await marketplaceQuery(
        `
          update public.marketplace_user_listings
          set
            quantity_available = quantity_available - $2,
            status = case when quantity_available - $2 <= 0 then 'sold_out' else status end,
            updated_at = now()
          where id = $1
            and seller_uid = $3
            and status = 'active'
            and quantity_available >= $2
          returning card_id
        `,
        [item.listingId, item.quantity, item.sellerUid],
      );
      const row = result.rows[0];
      if (!row) {
        const error = new Error(`Listing ${item.listingId} is no longer available.`);
        error.statusCode = 409;
        throw error;
      }
      decremented.push({
        listingId: item.listingId,
        quantity: item.quantity,
        cardId: row.card_id || item.card.id,
      });
    }
  } catch (error) {
    for (const entry of decremented.reverse()) {
      if (entry.external) continue;
      await marketplaceQuery(
        `
          update public.marketplace_user_listings
          set
            quantity_available = quantity_available + $2,
            status = case when status = 'sold_out' then 'active' else status end,
            updated_at = now()
          where id = $1
        `,
        [entry.listingId, entry.quantity],
      ).catch((rollbackError) => {
        console.error('marketplace listing rollback failed', rollbackError);
      });
    }
    throw error;
  }

  for (const cardId of [...new Set(decremented.filter((entry) => !entry.external).map((entry) => entry.cardId).filter(Boolean))]) {
    await marketplaceQuery(
      'select public.refresh_marketplace_blueprint_price_summary($1)',
      [cardId],
    ).catch((error) => {
      console.error('marketplace price summary refresh failed', error);
    });
  }
  return decremented;
}

async function createPaidOrder({ admin, firestore, decoded, body }) {
  const items = normalizedItems(body?.items);
  if (items.length === 0) {
    const error = new Error('Add at least one available marketplace listing.');
    error.statusCode = 400;
    throw error;
  }
  const subtotalPkn = items.reduce((sum, item) => sum + item.totalPricePkn, 0);
  const fulfillmentMode = cleanFulfillmentMode(body?.fulfillmentMode);
  if (fulfillmentMode === 'nft_only' && items.some((item) => !item.nftAvailable && !item.reserveAvailable)) {
    const error = new Error('NFT-only checkout requires every item to have the NFT tag.');
    error.statusCode = 400;
    throw error;
  }
  const taxPkn = Math.max(0, numberValue(body?.taxPkn));
  const shippingPkn = fulfillmentMode === 'nft_only'
    ? 0
    : Math.max(0, numberValue(body?.shippingPkn));
  const computedTotal = subtotalPkn + taxPkn + shippingPkn;
  const requestedTotal = numberValue(body?.totalPkn, computedTotal);
  const totalPkn = Math.max(computedTotal, requestedTotal);
  if (!Number.isFinite(totalPkn) || totalPkn <= 0) {
    const error = new Error('Order total is invalid.');
    error.statusCode = 400;
    throw error;
  }

  if (fulfillmentMode !== 'nft_only') {
    assertCardTraderCheckoutCanProceed(items, body, process.env);
  }
  await verifyCardTraderLiveItems(items);
  await verifyAndDecrementListings(items);

  const orderRef = firestore.collection('orders').doc();
  const buyerBalanceRef = firestore.collection('balances').doc(decoded.uid);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const sellerUids = uniqueSellerUids(items);
  const sellerTotals = new Map();
  for (const item of items) {
    sellerTotals.set(item.sellerUid, (sellerTotals.get(item.sellerUid) || 0) + item.totalPricePkn);
  }

  let orderData = null;
  try {
    await firestore.runTransaction(async (transaction) => {
      const buyerBalance = await transaction.get(buyerBalanceRef);
      const available = numberValue(buyerBalance.data()?.availablePkn);
      if (available < totalPkn) {
        const error = new Error('Your account balance is too low.');
        error.statusCode = 400;
        throw error;
      }

      transaction.set(
        buyerBalanceRef,
        {
          availablePkn: admin.firestore.FieldValue.increment(-totalPkn),
          updatedAt: now,
        },
        { merge: true },
      );
      transaction.set(firestore.collection('ledger_entries').doc(), {
        uid: decoded.uid,
        type: 'marketplace_order_paid',
        amountPkn: -totalPkn,
        orderId: orderRef.id,
        createdAt: now,
      });

      for (const [sellerUid, amountPkn] of sellerTotals.entries()) {
        const sellerBalanceRef = firestore.collection('balances').doc(sellerUid);
        transaction.set(
          sellerBalanceRef,
          {
            availablePkn: admin.firestore.FieldValue.increment(amountPkn),
            updatedAt: now,
          },
          { merge: true },
        );
        transaction.set(firestore.collection('ledger_entries').doc(), {
          uid: sellerUid,
          type: 'marketplace_sale_paid',
          amountPkn,
          orderId: orderRef.id,
          buyerUid: decoded.uid,
          createdAt: now,
        });
      }

      orderData = {
        uid: decoded.uid,
        buyerUid: decoded.uid,
        buyerEmail: cleanText(decoded.email || body?.buyerEmail, 320).toLowerCase(),
        items,
        subtotalPkn,
        taxPkn,
        shippingPkn,
        totalPkn,
        status: 'paid',
        paymentStatus: 'paid',
        fulfillmentStatus: fulfillmentMode === 'nft_only'
          ? 'nft_ownership_recorded'
          : 'awaiting_seller_confirmation',
        fulfillmentMode,
        sellerUids,
        source: 'marketplace_checkout',
        createdAt: now,
        paidAt: now,
        updatedAt: now,
      };
      transaction.set(orderRef, orderData);
      if (fulfillmentMode === 'nft_only') {
        for (const item of items) {
          const collectionRef = firestore.collection('user_card_collections').doc();
          transaction.set(
            collectionRef,
            collectionPayloadForItem({
              uid: decoded.uid,
              item,
              orderId: orderRef.id,
              now,
            }),
          );
        }
      }
    });
  } catch (error) {
    for (const item of items) {
      if (isCardTraderLiveItem(item)) continue;
      await marketplaceQuery(
        `
          update public.marketplace_user_listings
          set
            quantity_available = quantity_available + $2,
            status = case when status = 'sold_out' then 'active' else status end,
            updated_at = now()
          where id = $1
        `,
        [item.listingId, item.quantity],
      ).catch((rollbackError) => {
        console.error('marketplace listing rollback failed', rollbackError);
      });
    }
    throw error;
  }

  const notification = orderData.fulfillmentMode === 'nft_only'
    ? { ok: true, skipped: true, reason: 'NFT-only checkout does not start physical seller fulfillment.' }
    : await sendSellerSaleNotificationsForPaidOrder({
      admin,
      firestore,
      orderId: orderRef.id,
      orderData,
    }).catch((error) => {
      console.error('marketplace seller notification failed', error);
      return { ok: false, error: error.message || 'Seller notification failed.' };
    });

  const cardTraderPurchase = orderData.fulfillmentMode === 'nft_only'
    ? { ok: true, skipped: true, reason: 'NFT-only checkout keeps reserve custody and skips live CardTrader buy-through.' }
    : await buyCardTraderItemsForPaidOrder({
      admin,
      firestore,
      orderId: orderRef.id,
      orderData,
      env: body?.cardTraderDryRun === true
        ? { ...process.env, CARDTRADER_BUY_DRY_RUN: 'true', CARDTRADER_BUY_ENABLED: '' }
        : process.env,
    }).catch((error) => {
      console.error('cardtrader buy-through failed', {
        code: error.code || '',
        statusCode: error.statusCode || 500,
        message: error.message,
      });
      return {
        ok: false,
        error: error.message || 'CardTrader buy-through failed.',
        code: error.code,
      };
    });
  if (orderData.fulfillmentMode !== 'nft_only' && (orderData.items || []).some(isCardTraderLiveItem)) {
    orderData.cardTraderPurchase = cardTraderPurchase;
    if (cardTraderPurchase.ok && cardTraderPurchase.dryRun) {
      orderData.fulfillmentStatus = 'external_purchase_dry_run';
    } else if (cardTraderPurchase.ok) {
      orderData.fulfillmentStatus = 'awaiting_cardtrader_fulfillment';
    } else {
      orderData.fulfillmentStatus = 'external_purchase_failed';
    }
    await orderRef.set({
      cardTraderPurchase,
      fulfillmentStatus: orderData.fulfillmentStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true }).catch((error) => {
      console.error('marketplace order cardtrader status update failed', error);
    });
  }

  return {
    order: orderPayload(orderRef.id, orderData),
    sellerNotification: notification,
    cardTraderPurchase,
  };
}

async function sendNotificationsForExistingOrder({ admin, firestore, decoded, orderId }) {
  const orderRef = firestore.collection('orders').doc(orderId);
  const doc = await orderRef.get();
  if (!doc.exists) {
    const error = new Error('Marketplace order was not found.');
    error.statusCode = 404;
    throw error;
  }
  const data = doc.data() || {};
  const canAccess = data.uid === decoded.uid ||
    data.buyerUid === decoded.uid ||
    (Array.isArray(data.sellerUids) && data.sellerUids.includes(decoded.uid));
  if (!canAccess) {
    const error = new Error('You cannot access this marketplace order.');
    error.statusCode = 403;
    throw error;
  }
  const notification = await sendSellerSaleNotificationsForPaidOrder({
    admin,
    firestore,
    orderId,
    orderData: data,
  }).catch((error) => {
    console.error('marketplace seller notification failed', error);
    return { ok: false, error: error.message || 'Seller notification failed.' };
  });
  return {
    order: orderPayload(orderId, data),
    sellerNotification: notification,
  };
}

async function createNftShippingRequests({ admin, firestore, decoded, body }) {
  const rawIds = Array.isArray(body?.collectionItemIds)
    ? body.collectionItemIds
    : [body?.collectionItemId];
  const collectionItemIds = [...new Set(rawIds.map((value) => cleanOrderId(value)).filter(Boolean))];
  if (collectionItemIds.length === 0) {
    const error = new Error('Choose at least one NFT collection item to ship.');
    error.statusCode = 400;
    throw error;
  }
  if (collectionItemIds.length > 50) {
    const error = new Error('Request shipping for 50 NFTs or fewer at a time.');
    error.statusCode = 400;
    throw error;
  }
  const shippingAddress = shippingAddressFromBody(body?.shippingAddress);
  validateShippingAddress(shippingAddress);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = firestore.batch();
  const requests = [];

  for (const collectionItemId of collectionItemIds) {
    const itemRef = firestore.collection('user_card_collections').doc(collectionItemId);
    const itemDoc = await itemRef.get();
    const itemData = itemDoc.data() || {};
    if (!itemDoc.exists || itemData.uid !== decoded.uid) {
      const error = new Error(`NFT collection item ${collectionItemId} was not found.`);
      error.statusCode = 404;
      throw error;
    }
    if (itemData.ownershipType !== 'nft' &&
        itemData.fulfillmentMode !== 'nft_only' &&
        itemData.nftStatus !== 'owned') {
      const error = new Error(`Collection item ${collectionItemId} is not an owned NFT.`);
      error.statusCode = 400;
      throw error;
    }
    if (itemData.physicalShippingStatus && itemData.physicalShippingStatus !== 'not_requested') {
      const error = new Error(`Shipping is already requested for ${collectionItemId}.`);
      error.statusCode = 409;
      throw error;
    }

    const requestRef = firestore.collection('nft_shipping_requests').doc();
    const requestData = {
      uid: decoded.uid,
      collectionItemId,
      cardId: cleanText(itemData.cardId || itemData.blueprintId, 120),
      cardName: cleanText(itemData.cardName, 240),
      sourceOrderId: cleanText(itemData.sourceOrderId, 160),
      sourceListingId: cleanText(itemData.sourceListingId, 160),
      quantity: numberValue(itemData.quantity, 1),
      shippingAddress,
      notes: cleanText(body?.notes, 500),
      status: 'pending_ops_review',
      chargeStatus: 'not_charged',
      externalFulfillmentStatus: 'not_sent',
      createdAt: now,
      updatedAt: now,
    };
    batch.set(requestRef, requestData);
    batch.set(itemRef, {
      physicalShippingStatus: 'requested',
      physicalShippingRequestId: requestRef.id,
      physicalShippingRequestedAt: now,
      updatedAt: now,
    }, { merge: true });
    requests.push(requestPayload(requestRef.id, requestData));
  }

  await batch.commit();
  return {
    request: requests[0],
    requests,
  };
}

module.exports = async function handler(req, res) {
  try {
    const decoded = await verifyBearerToken(req);
    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const action = cleanText(url.searchParams.get('action') || req.body?.action, 40);

    if (req.method === 'POST' && (!action || action === 'checkout')) {
      const result = await createPaidOrder({
        admin,
        firestore,
        decoded,
        body: req.body || {},
      });
      return res.status(200).json({ ok: true, ...result });
    }

    if (req.method === 'POST' && action === 'notify-sellers') {
      const orderId = cleanOrderId(url.searchParams.get('orderId') || req.body?.orderId);
      if (!orderId) {
        return res.status(400).json({ error: 'Order id is required.' });
      }
      const result = await sendNotificationsForExistingOrder({
        admin,
        firestore,
        decoded,
        orderId,
      });
      return res.status(200).json({ ok: true, ...result });
    }

    if (req.method === 'POST' && action === 'nft-shipping-request') {
      const result = await createNftShippingRequests({
        admin,
        firestore,
        decoded,
        body: req.body || {},
      });
      return res.status(200).json({ ok: true, ...result });
    }

    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  } catch (error) {
    console.error('marketplace-orders failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace order failed.',
    });
  }
};

module.exports._test = {
  cleanOrderId,
  buyCardTraderItemsForPaidOrder,
  assertCardTraderBuyConfigured,
  assertCardTraderCartIsEmpty,
  assertCardTraderCheckoutCanProceed,
  cardTraderCartItems,
  cardTraderBuyEnabled,
  cardTraderDryRun,
  cardTraderProductIdForItem,
  configuredCardTraderBuyToken,
  cleanFulfillmentMode,
  collectionPayloadForItem,
  createNftShippingRequests,
  createPaidOrder,
  isCardTraderLiveItem,
  normalizeItem,
  normalizedItems,
  orderPayload,
  shippingAddressFromBody,
  verifyCardTraderLiveItems,
};
