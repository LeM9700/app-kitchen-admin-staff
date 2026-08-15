# API Kitchen Demo RC1 Script

## Environment

- Backend: `C:\Users\melbo\workspace\pizza\api-pizza`
- Frontend: `C:\Users\melbo\workspace\pizza\app-admin-staff`
- Seed: `api-pizza\scripts\seed_pizza_test.sql`
- Database: PostgreSQL local from `DATABASE_URL` in backend `.env`
- Redis: `redis://localhost:6379/`
- MongoDB dashboard store: `mongodb://localhost:27017/`
- Worker: `arq worker.main.WorkerSettings`
- API URL: `http://127.0.0.1:8000/api/v1`
- WebSocket URL: `ws://127.0.0.1:8000/api/v1/ws/notifications?tenant_slug=pizza_test`
- Stripe Connect callbacks for local demo:
  `http://localhost:8080/stripe/connect/return` and
  `http://localhost:8080/stripe/connect/refresh`

Do not display secrets, JWTs, refresh tokens, webhook secrets, SMTP credentials,
Cloudinary credentials, APNs keys, FCM JSON, or the shared demo password.

## Demo Data

- Tenant: `pizza_test` / `PizzaTEST`
- Admin: `pizza@test.com`
- Staff kitchen: `staff.cuisine@test.com`
- Staff delivery: `staff.livraison@test.com`
- Customers: `client.alice@test.com`, `client.yanis@test.com`
- Catalog: pizza categories, products, variants, extras, media, allergens, stock availability
- Operations: pending, confirmed, preparing, delivered and cancelled orders
- HR: one active establishment, employee profiles, scheduled shifts and one cancelled shift
- Stock: ingredients, recipes, movements and one low-stock alert
- Promotions/loyalty/delivery: `PIZZA10`, `WELCOME5`, loyalty account data and two delivery zones

## Start

```powershell
cd C:\Users\melbo\workspace\pizza\api-pizza
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
.\.venv\Scripts\arq.exe worker.main.WorkerSettings
```

```powershell
cd C:\Users\melbo\workspace\pizza\app-admin-staff
flutter pub get --no-precompile --no-example
flutter build web --no-wasm-dry-run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1 --dart-define=DEFAULT_TENANT_SLUG=pizza_test --dart-define=APP_ENV=development --dart-define=STRIPE_CONNECT_RETURN_URL=http://localhost:8080/stripe/connect/return --dart-define=STRIPE_CONNECT_REFRESH_URL=http://localhost:8080/stripe/connect/refresh
```

## 3-5 Minute Flow

1. Login as Staff kitchen and confirm the protected shell loads after `/auth/me`.
2. Open Service orders, select a paid confirmed order, and open the detail.
3. Open Kitchen, mark the order preparing, mark each item ready, then mark the order ready.
4. Keep a second Staff session open and confirm a real-time `order.confirmed` update appears after confirming a pending order.
5. Login as Admin and open Dashboard, Catalog, Team, Planning, Settings, Stock, Finance, Promotions, Loyalty and Delivery.
6. In Catalog, save an existing product without visible content changes.
7. In Team, open a staff user and save current permissions.
8. In Planning, create a shift, update its break duration, then cancel it with `PATCH status="cancelled"`.
9. In Finance, read summaries/details only. Do not run live Stripe charges or refunds.
10. In Delivery, show zones/check smoke. Map editing remains non-production debt.

## Fallbacks

- If `flutter pub get` hangs, use `flutter pub get --no-precompile --no-example`.
- If `flutter build web` hangs during Wasm dry-run, use `--no-wasm-dry-run`.
- If real-time does not update, verify backend lifespan starts the Redis subscriber and Redis is reachable.
- If demo data drifts after smoke tests, re-run `scripts\seed_pizza_test.sql`.
- If Stripe Connect is opened, use only local callback URLs in development and do not paste secrets into the UI.

## RC1 Boundaries

- No physical HR shift delete in the UI; cancel via `PATCH status="cancelled"`.
- No production-grade delivery map editor.
- Dashboard displays only real backend data; no fabricated metrics.
- Production readiness still requires real Stripe/Connect callbacks, secrets, monitoring, backups, and deployment hardening.
