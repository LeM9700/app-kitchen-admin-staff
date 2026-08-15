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
DEFAULT_TENANT_SLUG=pizza_test
```

The app keeps the API as source of truth. Offline support queues allowed service actions locally and exposes manual sync from settings.
