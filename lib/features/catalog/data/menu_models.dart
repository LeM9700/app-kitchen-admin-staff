import 'package:app_admin_staff/core/utils/json.dart';

class MenuAdminList {
  const MenuAdminList({
    required this.items,
    required this.total,
    required this.page,
    required this.pages,
  });

  final List<MenuAdmin> items;
  final int total;
  final int page;
  final int pages;

  factory MenuAdminList.fromJson(Map<String, dynamic> json) {
    return MenuAdminList(
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => MenuAdmin.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
      total: readInt(json['total']),
      page: readInt(json['page'], fallback: 1),
      pages: readInt(json['pages'], fallback: 1),
    );
  }
}

class MenuAdmin {
  const MenuAdmin({
    required this.id,
    required this.name,
    required this.fixedPrice,
    required this.displayOrder,
    required this.isActive,
    required this.groups,
    required this.isPublishable,
    required this.validationErrors,
    this.description,
    this.imageUrl,
    this.availableFrom,
    this.availableUntil,
  });

  final int id;
  final String name;
  final String? description;
  final double fixedPrice;
  final String? imageUrl;
  final int displayOrder;
  final bool isActive;
  final DateTime? availableFrom;
  final DateTime? availableUntil;
  final List<MenuGroupAdmin> groups;
  final bool isPublishable;
  final List<String> validationErrors;

  int get productCount =>
      groups.fold(0, (total, group) => total + group.items.length);

  factory MenuAdmin.fromJson(Map<String, dynamic> json) {
    return MenuAdmin(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      fixedPrice: readDouble(json['fixed_price']),
      imageUrl: json['image_url']?.toString(),
      displayOrder: readInt(json['display_order']),
      isActive: readBool(json['is_active']),
      availableFrom: DateTime.tryParse(json['available_from']?.toString() ?? ''),
      availableUntil:
          DateTime.tryParse(json['available_until']?.toString() ?? ''),
      groups: (json['groups'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                MenuGroupAdmin.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      isPublishable: readBool(json['is_publishable']),
      validationErrors: (json['validation_errors'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
    );
  }
}

class MenuGroupAdmin {
  const MenuGroupAdmin({
    required this.id,
    required this.menuId,
    required this.name,
    required this.minChoices,
    required this.maxChoices,
    required this.displayOrder,
    required this.items,
  });

  final int id;
  final int menuId;
  final String name;
  final int minChoices;
  final int maxChoices;
  final int displayOrder;
  final List<MenuGroupItemAdmin> items;

  factory MenuGroupAdmin.fromJson(Map<String, dynamic> json) {
    return MenuGroupAdmin(
      id: readInt(json['id']),
      menuId: readInt(json['menu_id']),
      name: json['name']?.toString() ?? '',
      minChoices: readInt(json['min_choices'], fallback: 1),
      maxChoices: readInt(json['max_choices'], fallback: 1),
      displayOrder: readInt(json['display_order']),
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                MenuGroupItemAdmin.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
    );
  }
}

class MenuGroupItemAdmin {
  const MenuGroupItemAdmin({
    required this.id,
    required this.groupId,
    required this.productId,
    required this.displayOrder,
    required this.productName,
    required this.productIsActive,
    this.productExternalId,
  });

  final int id;
  final int groupId;
  final int productId;
  final int displayOrder;
  final String productName;
  final bool productIsActive;
  final String? productExternalId;

  bool get isPosManaged =>
      productExternalId != null && productExternalId!.trim().isNotEmpty;

  factory MenuGroupItemAdmin.fromJson(Map<String, dynamic> json) {
    return MenuGroupItemAdmin(
      id: readInt(json['id']),
      groupId: readInt(json['group_id']),
      productId: readInt(json['product_id']),
      displayOrder: readInt(json['display_order']),
      productName: json['product_name']?.toString() ?? '',
      productIsActive: readBool(json['product_is_active']),
      productExternalId: json['product_external_id']?.toString(),
    );
  }
}

class MenuDraft {
  const MenuDraft({
    required this.name,
    required this.fixedPrice,
    this.description,
    this.imageUrl,
    this.displayOrder = 0,
    this.isActive = false,
    this.changeReason,
  });

  final String name;
  final String? description;
  final double fixedPrice;
  final String? imageUrl;
  final int displayOrder;
  final bool isActive;
  final String? changeReason;

  Map<String, dynamic> toJson({bool includeChangeReason = false}) => {
        'name': name.trim(),
        'description': _optional(description),
        'fixed_price': fixedPrice,
        'image_url': _optional(imageUrl),
        'display_order': displayOrder,
        'is_active': isActive,
        if (includeChangeReason && _optional(changeReason) != null)
          'change_reason': _optional(changeReason),
      };
}

class MenuGroupDraft {
  const MenuGroupDraft({
    required this.name,
    required this.minChoices,
    required this.maxChoices,
    this.displayOrder = 0,
  });

  final String name;
  final int minChoices;
  final int maxChoices;
  final int displayOrder;

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'min_choices': minChoices,
        'max_choices': maxChoices,
        'display_order': displayOrder,
      };
}

String? _optional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
