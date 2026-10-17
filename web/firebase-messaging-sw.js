/* Service worker for web push (registered by firebase_messaging on getToken).
 *
 * It deliberately loads no Firebase SDK and holds no configuration or keys:
 * it only displays what the server sent and opens the app when it is clicked.
 * Content comes from the push payload (title/body written by Cloud Functions,
 * which never includes amounts, marks or other private details).
 */
'use strict';

const APP_ROUTE_ALLOWLIST = ['/notifications'];

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    return; // not ours / not JSON: show nothing rather than something wrong
  }
  const n = payload.notification || {};
  const data = payload.data || {};
  const title = n.title || data.title || 'EazySchool 360';
  const options = {
    body: n.body || data.body || '',
    icon: n.icon || '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    // The same tag replaces an earlier copy of the same notification.
    tag: n.tag || data.notificationId || undefined,
    data: { route: data.route || '/notifications' },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const requested = (event.notification.data && event.notification.data.route) || '/notifications';
  // Never navigate to anything the payload names beyond the known routes.
  const route = APP_ROUTE_ALLOWLIST.includes(requested) ? requested : '/notifications';
  const target = new URL('/#' + route, self.location.origin).href;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      for (const w of windows) {
        if (new URL(w.url).origin === self.location.origin && 'focus' in w) {
          w.postMessage({ type: 'push-open', route });
          return w.focus().then((c) => ('navigate' in c ? c.navigate(target) : c));
        }
      }
      return self.clients.openWindow(target);
    }),
  );
});
