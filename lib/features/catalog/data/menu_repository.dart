import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/features/catalog/data/menu_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final menuRepositoryProvider = Provider<MenuRepository>((ref) {
  return MenuRepository(ref.watch(apiClientProvider));
});

final adminMenusProvider = FutureProvider.autoDispose<List<MenuAdmin>>((ref) {
  return ref.watch(menuRepositoryProvider).listMenus();
});

class MenuRepository {
  const MenuRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<MenuAdmin>> listMenus({int pageSize = 100}) async {
    final response = await _apiClient.get(
      ApiEndpoints.catalogAdminMenus,
      queryParameters: {'page': 1, 'page_size': pageSize},
    );
    return MenuAdminList.fromJson(response.data as Map<String, dynamic>).items;
  }

  Future<MenuAdmin> getMenu(int menuId) async {
    final response = await _apiClient.get(
      ApiEndpoints.catalogAdminMenu(menuId),
    );
    return MenuAdmin.fromJson(response.data as Map<String, dynamic>);
  }

  Future<MenuAdmin> createMenu(MenuDraft draft) async {
    final response = await _apiClient.post(
      ApiEndpoints.catalogAdminMenus,
      data: draft.toJson(),
    );
    return MenuAdmin.fromJson(response.data as Map<String, dynamic>);
  }

  Future<MenuAdmin> updateMenu(int menuId, MenuDraft draft) async {
    final response = await _apiClient.put(
      ApiEndpoints.catalogAdminMenu(menuId),
      data: draft.toJson(includeChangeReason: true),
    );
    return MenuAdmin.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteMenu(int menuId) async {
    await _apiClient.delete(ApiEndpoints.catalogAdminMenu(menuId));
  }

  Future<MenuAdmin> createGroup(int menuId, MenuGroupDraft draft) async {
    final response = await _apiClient.post(
      ApiEndpoints.catalogAdminMenuGroups(menuId),
      data: draft.toJson(),
    );
    return MenuAdmin.fromJson(response.data as Map<String, dynamic>);
  }

  Future<MenuAdmin> updateGroup(
    int menuId,
    int groupId,
    MenuGroupDraft draft,
  ) async {
    final response = await _apiClient.put(
      ApiEndpoints.catalogAdminMenuGroup(menuId, groupId),
      data: draft.toJson(),
    );
    return MenuAdmin.fromJson(response.data as Map<String, dynamic>);
  }

  Future<MenuAdmin> deleteGroup(int menuId, int groupId) async {
    final response = await _apiClient.delete(
      ApiEndpoints.catalogAdminMenuGroup(menuId, groupId),
    );
    return MenuAdmin.fromJson(response.data as Map<String, dynamic>);
  }

  Future<MenuAdmin> addProduct(
    int menuId,
    int groupId,
    int productId, {
    int displayOrder = 0,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.catalogAdminMenuGroupItems(menuId, groupId),
      data: {'product_id': productId, 'display_order': displayOrder},
    );
    return MenuAdmin.fromJson(response.data as Map<String, dynamic>);
  }

  Future<MenuAdmin> removeProduct(
    int menuId,
    int groupId,
    int itemId,
  ) async {
    final response = await _apiClient.delete(
      ApiEndpoints.catalogAdminMenuGroupItem(menuId, groupId, itemId),
    );
    return MenuAdmin.fromJson(response.data as Map<String, dynamic>);
  }
}
