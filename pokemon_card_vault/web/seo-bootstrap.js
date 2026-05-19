(function () {
  window.pokoinClearFlutterCache = async function () {
    if ('serviceWorker' in navigator) {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.map((registration) => registration.unregister()));
    }
    if ('caches' in window) {
      const cacheNames = await caches.keys();
      await Promise.all(cacheNames.map((cacheName) => caches.delete(cacheName)));
    }
  };

  window.pokoinClearFlutterCache()
    .catch(() => {})
    .finally(() => {
      const script = document.createElement('script');
      script.src = `/flutter_bootstrap.js?v=${Date.now()}`;
      script.async = true;
      document.body.appendChild(script);
    });
})();
