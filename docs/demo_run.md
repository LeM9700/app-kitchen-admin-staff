# Sprint 6 Demo Run

## Backend

```powershell
cd C:\Users\melbo\workspace\pizza\api-pizza
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

The demo tenant data strategy is the existing backend seed:

```powershell
psql $env:DATABASE_URL -f scripts\seed_pizza_test.sql
```

Expected seed scope: tenant `pizza_test`, admin/staff/customer users, default
establishment, catalog categories/products/extras, stock ingredients, orders,
payments, loyalty, promotions, delivery zones, HR employees/shifts.

## Frontend

```powershell
cd C:\Users\melbo\workspace\pizza\app-admin-staff
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1 --dart-define=DEFAULT_TENANT_SLUG=pizza_test
```

Production builds must set non-example Stripe callback URLs:

```powershell
--dart-define=APP_ENV=production
--dart-define=STRIPE_CONNECT_RETURN_URL=https://admin.example.tld/stripe/connect/return
--dart-define=STRIPE_CONNECT_REFRESH_URL=https://admin.example.tld/stripe/connect/refresh
```

`Env.validateStartupConfig()` rejects invalid URLs and `example.com` callback
hosts in production.

## Demo Flow

1. Login with a seeded staff/admin account for tenant `pizza_test`.
2. Confirm bootstrap reaches `/auth/me` before the protected shell renders.
3. Verify the selected establishment appears in the sidebar footer.
4. Service: open `/orders`, confirm a paid pending order, cancel only with a
   reason, and verify slow/double-click mutations do not duplicate requests.
5. Kitchen: open `/kitchen`, mark items as preparing/ready, then mark all ready.
6. Admin: catalog/settings/team/HR screens should use real API permissions and
   show backend 403/409/422 messages directly.
7. HR shifts: list/create/update/cancel via `PATCH status="cancelled"`;
   physical delete stays disabled until backend DELETE exists.

## Tests

```powershell
dart format lib test integration_test
dart analyze --fatal-infos
flutter analyze --no-pub
flutter test --no-pub
flutter test integration_test --dart-define=DEMO_E2E=true
```

Backend targeted checks after Sprint 6:

```powershell
cd C:\Users\melbo\workspace\pizza\api-pizza
python -m pytest tests\test_auth.py tests\test_allergen_notifications.py
ruff check app tests
```

## Known Demo Debts

- `DASHBOARD_DATA_GAP`: dashboard tiles must stay limited to real backend
  metrics; no invented revenue or operational KPIs.
- `DELIVERY_MAP_DEBT`: delivery zones have no production-grade map editor until
  the backend/frontend GeoJSON contract is expanded.
- `NOTIFICATION_API_GAP`: real-time WebSocket/push is present, but there is no
  persistent notification center API yet.
