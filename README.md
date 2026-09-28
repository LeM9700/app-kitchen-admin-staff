# O'Pizza Admin/Staff

Flutter app for restaurant staff and tenant admins.

Current scope:

- real JWT login against `api-pizza`;
- responsive shell for mobile, tablet and desktop;
- role/permission-aware navigation;
- service board for active orders;
- manual checkout flow using `POST /orders/manual`;
- catalog availability override and preparation station edit;
- kitchen/counter item preparation flow;
- stock supply, ingredient batches and admin adjustment requests;
- payments list, summary, admin refunds, CSV export and Stripe Terminal intent;
- Stripe Connect onboarding/dashboard links;
- delivery zones and address coverage check;
- loyalty config/rules/rewards/stats;
- promotions admin list/create/toggle/delete;
- tenant status, manual closure and shared print config;
- WebSocket realtime notifications with order refresh and alert sound;
- persistent KDS remote pairing with protected QR payloads;
- mobile QR scan flow for Service, Kitchen and Counter remotes;
- fullscreen operational mode for Service, Kitchen and Counter;
- local offline action queue and print job queue.

## Run

Flutter is not available in this Codex shell. On a machine with Flutter:

```powershell
cd app-admin-staff
flutter create .
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

Tests:

```powershell
flutter test
```

Optional compile-time values:

```text
API_BASE_URL=http://127.0.0.1:8000/api/v1
APP_PUBLIC_URL=https://your-admin-staff.netlify.app
DEFAULT_TENANT_SLUG=pizza_test
KDS_INTERACTION_MODE=touch # demo-only, default: wall
```

The app keeps the API as source of truth. Offline support queues allowed service actions locally and exposes manual sync from settings.

## KDS remote operations

Service (`/orders`), Kitchen (`/kitchen`) and Counter (`/counter`) can expose an operational remote QR
when a KDS screen is active and marked as remote-compatible. The QR opens `/kitchen/remote` with a
protected `pair` payload, not the clear 6-digit code. The mobile app resolves that payload through the
backend, pre-fills the temporary pairing code, then the staff user confirms the pairing.

On mobile, the same three tabs show an in-app QR scanner. The staff user must already be connected and
must have the preparation permission; native iOS/Android deep links are intentionally out of scope for
this sprint. Camera permissions are declared for Android and iOS.

`APP_PUBLIC_URL` is optional but recommended for Netlify builds so desktop QR codes contain an absolute
URL such as `https://your-admin-staff.netlify.app/kitchen/remote?pair=...`. When it is omitted, the QR
uses a relative `/kitchen/remote?pair=...` URL.

The fullscreen button on Service, Kitchen and Counter hides the admin navigation during service and can
be toggled off from the same screen.

The KDS phone remote requires a backend exposing `/api/v1/kds/*` persistent pairing endpoints; it stores only the temporary remote session token in secure local storage and validates it on startup.
