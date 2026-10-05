/// Only account pages are gated. The Wallet overview is public; its account
/// actions ask for sign-in without exposing balances or submitting operations.
bool requiresAccountForRoute(String matchedLocation) => const {
      '/swap',
      '/profile',
      '/inventory',
      '/collection',
      '/nft',
      '/checkout',
      '/orders',
      '/marketplace/connect',
    }.contains(matchedLocation);
