{{flutter_js}}
{{flutter_build_config}}

// Palay Patrol web start-up.
//
// * CanvasKit is loaded from this site (canvaskit/ in the build) instead of
//   Google's CDN, so the app shell can be cached and opened without signal.
// * Flutter's own service worker is deprecated (it now only unregisters
//   itself), so it is not registered here. offline_sw.js caches the app shell
//   instead; observations, photos and records are already kept in the
//   browser (SQLite on WebAssembly + IndexedDB) and sent when signal is back.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});

if ('serviceWorker' in navigator && window.isSecureContext) {
  window.addEventListener('load', () => {
    navigator.serviceWorker
      .register('offline_sw.js', { scope: './' })
      .then(() => navigator.serviceWorker.ready)
      .then((reg) => {
        // The first visit loads the fallback text font before the worker is
        // in charge: hand it the font URLs so they are cached too.
        const send = () => {
          const urls = performance
            .getEntriesByType('resource')
            .map((e) => e.name)
            .filter((n) => n.startsWith('https://fonts.gstatic.com/'));
          if (urls.length && reg.active) reg.active.postMessage({ type: 'cache-urls', urls });
        };
        setTimeout(send, 4000);
        setTimeout(send, 20000);
      })
      .catch((e) => console.warn('[offline] service worker not registered:', e));
  });
}
