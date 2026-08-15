class PaginatedResult<T> {
  const PaginatedResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;

  factory PaginatedResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> value) fromJson,
  ) {
    final rawItems = json['items'];
    return PaginatedResult<T>(
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((value) => fromJson(Map<String, dynamic>.from(value)))
              .toList()
          : const [],
      total: _readInt(json['total'] ?? json['total_count']),
      page: _readInt(json['page'], fallback: 1),
      pageSize: _readInt(json['page_size'], fallback: 50),
    );
  }
}

int _readInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
