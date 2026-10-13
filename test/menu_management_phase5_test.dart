import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/catalog/data/menu_models.dart';
import 'package:app_admin_staff/features/catalog/data/menu_repository.dart';
import 'package:app_admin_staff/features/catalog/presentation/menu_management_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MenuRepository', () {
    test('parse les menus et respecte les contrats des mutations', () async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        if (options.method == 'GET') {
          return _jsonResponse({
            'items': [_menuJson()],
            'total': 1,
            'page': 1,
            'pages': 1,
          });
        }
        if (options.method == 'DELETE' &&
            options.path == ApiEndpoints.catalogAdminMenu(12)) {
          return _jsonResponse(null, statusCode: 204);
        }
        return _jsonResponse(_menuJson());
      });
      final repository = MenuRepository(api);

      final menus = await repository.listMenus();
      expect(menus, hasLength(1));
      expect(menus.single.name, 'Menu midi');
      expect(menus.single.groups.single.items.single.isPosManaged, isTrue);

      await repository.createMenu(
        const MenuDraft(name: 'Soir', fixedPrice: 19.5),
      );
      await repository.updateMenu(
        12,
        const MenuDraft(
          name: 'Soir publie',
          fixedPrice: 20,
          isActive: true,
          changeReason: 'Validation phase 7',
        ),
      );
      await repository.createGroup(
        12,
        const MenuGroupDraft(
          name: 'Boisson',
          minChoices: 1,
          maxChoices: 1,
        ),
      );
      await repository.updateGroup(
        12,
        31,
        const MenuGroupDraft(
          name: 'Boissons',
          minChoices: 1,
          maxChoices: 2,
        ),
      );
      await repository.addProduct(12, 31, 8, displayOrder: 2);
      await repository.removeProduct(12, 31, 44);
      await repository.deleteGroup(12, 31);
      await repository.deleteMenu(12);

      expect(
        requests.firstWhere((request) => request.method == 'GET').queryParameters,
        {'page': 1, 'page_size': 100},
      );
      final create = requests.firstWhere(
        (request) =>
            request.method == 'POST' &&
            request.path == ApiEndpoints.catalogAdminMenus,
      );
      expect(create.data['name'], 'Soir');
      expect(create.data['fixed_price'], 19.5);
      expect(create.data['is_active'], isFalse);

      final update = requests.firstWhere(
        (request) =>
            request.method == 'PUT' &&
            request.path == ApiEndpoints.catalogAdminMenu(12),
      );
      expect(update.data['fixed_price'], 20);
      expect(update.data['is_active'], isTrue);
      expect(update.data['change_reason'], 'Validation phase 7');

      final updateGroup = requests.firstWhere(
        (request) =>
            request.method == 'PUT' &&
            request.path == ApiEndpoints.catalogAdminMenuGroup(12, 31),
      );
      expect(updateGroup.data['name'], 'Boissons');
      expect(updateGroup.data['max_choices'], 2);

      final addProduct = requests.firstWhere(
        (request) =>
            request.method == 'POST' &&
            request.path == ApiEndpoints.catalogAdminMenuGroupItems(12, 31),
      );
      expect(addProduct.data, {'product_id': 8, 'display_order': 2});
      expect(
        requests.any(
          (request) =>
              request.method == 'DELETE' &&
              request.path ==
                  ApiEndpoints.catalogAdminMenuGroupItem(12, 31, 44),
        ),
        isTrue,
      );
      expect(
        requests.any(
          (request) =>
              request.method == 'DELETE' &&
              request.path == ApiEndpoints.catalogAdminMenuGroup(12, 31),
        ),
        isTrue,
      );
    });
  });

  group('MenuManagementPage', () {
    testWidgets('explique le blocage et desactive la publication',
        (tester) async {
      await _pumpPage(
        tester,
        menus: [_menu(isPublishable: false, validationErrors: const ['Ajoutez un dessert.'])],
      );

      expect(find.text('Avant publication'), findsOneWidget);
      expect(find.textContaining('Ajoutez un dessert.'), findsOneWidget);
      final publish = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Publier'),
      );
      expect(publish.onPressed, isNull);
      expect(find.text('Apercu client'), findsOneWidget);
    });

    testWidgets('valide le formulaire avant la creation', (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        return _jsonResponse(_menuJson(name: 'Menu soir'));
      });
      await _pumpPage(tester, menus: const [], api: api);

      await tester.tap(find.widgetWithText(FilledButton, 'Nouveau menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Creer'));
      await tester.pump();

      expect(find.text('Le nom est obligatoire.'), findsOneWidget);
      expect(find.text('Prix invalide.'), findsOneWidget);
      expect(requests, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom'),
        '  Menu soir  ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Prix fixe'),
        '19,50',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Creer'));
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(requests.single.path, ApiEndpoints.catalogAdminMenus);
      expect(requests.single.data['name'], 'Menu soir');
      expect(requests.single.data['fixed_price'], 19.5);
    });

    testWidgets('ajoute un produit par recherche sans ID technique',
        (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        return _jsonResponse(_menuJson());
      });
      await _pumpPage(
        tester,
        menus: [_menu(items: const [])],
        products: const [_product],
        api: api,
        size: const Size(390, 844),
      );

      await tester.drag(
        find.byType(ListView).last,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Ajouter des produits'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'marg');
      await tester.pump();
      expect(find.text('Margherita'), findsOneWidget);
      expect(find.textContaining('Conformite a completer'), findsOneWidget);
      await tester.tap(find.text('Margherita'));
      await tester.pumpAndSettle();

      final add = requests.singleWhere(
        (request) =>
            request.method == 'POST' &&
            request.path == ApiEndpoints.catalogAdminMenuGroupItems(12, 31),
      );
      expect(add.data['product_id'], 8);
      expect(find.text('Margherita ajoute.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ajoute puis supprime un groupe avec confirmation',
        (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        return _jsonResponse(_menuJson());
      });
      await _pumpPage(tester, menus: [_menu()], api: api);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Ajouter un groupe'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom du groupe'),
        'Dessert',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();

      final createGroup = requests.singleWhere(
        (request) =>
            request.method == 'POST' &&
            request.path == ApiEndpoints.catalogAdminMenuGroups(12),
      );
      expect(createGroup.data['name'], 'Dessert');
      expect(createGroup.data['min_choices'], 1);
      expect(createGroup.data['max_choices'], 1);
      expect(find.text('Groupe ajoute.'), findsOneWidget);

      await tester.tap(find.byTooltip('Supprimer le groupe').first);
      await tester.pumpAndSettle();
      expect(find.text('Supprimer Pizza ?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();

      expect(
        requests.any(
          (request) =>
              request.method == 'DELETE' &&
              request.path == ApiEndpoints.catalogAdminMenuGroup(12, 31),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('reste consultable sans exposer les actions en lecture seule',
        (tester) async {
      await _pumpPage(
        tester,
        menus: [_menu()],
        permissions: const PermissionSet(
          role: 'staff',
          permissions: {AppPermission.catalogRead},
        ),
      );

      expect(find.text('Menu midi'), findsWidgets);
      expect(find.text('Apercu client'), findsOneWidget);
      expect(find.text('Nouveau menu'), findsNothing);
      expect(find.text('Modifier'), findsNothing);
      expect(find.text('Ajouter un groupe'), findsNothing);
      expect(find.text('Ajouter des produits'), findsNothing);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required List<MenuAdmin> menus,
  List<CatalogProduct> products = const [],
  ApiClient? api,
  PermissionSet permissions = const PermissionSet(
    role: 'admin',
    permissions: null,
  ),
  Size size = const Size(1400, 1000),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminMenusProvider.overrideWith((ref) async => menus),
        catalogProductsProvider.overrideWith((ref) async => products),
        currentPermissionSetProvider.overrideWithValue(permissions),
        if (api != null) menuRepositoryProvider.overrideWithValue(MenuRepository(api)),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const MenuManagementPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MenuAdmin _menu({
  bool isPublishable = true,
  List<String> validationErrors = const [],
  List<MenuGroupItemAdmin>? items,
}) {
  return MenuAdmin(
    id: 12,
    name: 'Menu midi',
    description: 'Une formule complete.',
    fixedPrice: 16.9,
    displayOrder: 0,
    isActive: false,
    isPublishable: isPublishable,
    validationErrors: validationErrors,
    groups: [
      MenuGroupAdmin(
        id: 31,
        menuId: 12,
        name: 'Pizza',
        minChoices: 1,
        maxChoices: 1,
        displayOrder: 0,
        items: items ??
            const [
              MenuGroupItemAdmin(
                id: 44,
                groupId: 31,
                productId: 8,
                displayOrder: 0,
                productName: 'Margherita',
                productIsActive: true,
                productExternalId: 'pos-8',
              ),
            ],
      ),
    ],
  );
}

const _product = CatalogProduct(
  id: 8,
  categoryId: 2,
  categoryName: 'Pizzas',
  name: 'Margherita',
  basePrice: 12,
  isActive: true,
  available: true,
  effectivePreparationStation: 'kitchen',
  regulatoryComplete: false,
);

Map<String, dynamic> _menuJson({String name = 'Menu midi'}) {
  return {
    'id': 12,
    'name': name,
    'description': 'Une formule complete.',
    'fixed_price': 16.9,
    'image_url': null,
    'display_order': 0,
    'is_active': false,
    'available_from': null,
    'available_until': null,
    'is_publishable': true,
    'validation_errors': <String>[],
    'groups': [
      {
        'id': 31,
        'menu_id': 12,
        'name': 'Pizza',
        'min_choices': 1,
        'max_choices': 1,
        'display_order': 0,
        'items': [
          {
            'id': 44,
            'group_id': 31,
            'product_id': 8,
            'display_order': 0,
            'product_name': 'Margherita',
            'product_is_active': true,
            'product_external_id': 'pos-8',
          },
        ],
      },
    ],
  };
}

ApiClient _client(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = _FakeAdapter(handler);
  return ApiClient(dio, _MemoryTokenStore());
}

ResponseBody _jsonResponse(Object? body, {int statusCode = 200}) {
  return ResponseBody.fromString(
    body == null ? '' : jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _MemoryTokenStore extends TokenStore {
  _MemoryTokenStore() : super(const FlutterSecureStorage());

  @override
  Future<String?> readAccessToken() async => 'access';

  @override
  Future<String?> readRefreshToken() async => 'refresh';

  @override
  Future<String?> readTenantSlug() async => 'pizza';
}
