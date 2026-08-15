import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(apiClientProvider));
});

final liveStatsProvider = FutureProvider.autoDispose<LiveStats>((ref) {
  return ref.watch(dashboardRepositoryProvider).liveStats();
});

final statsSummaryProvider = FutureProvider.autoDispose<StatsSummary>((ref) {
  return ref.watch(dashboardRepositoryProvider).summary();
});

final dailyStatsProvider = FutureProvider.autoDispose<List<DailyStats>>((ref) {
  return ref.watch(dashboardRepositoryProvider).daily();
});

final monthlyStatsProvider =
    FutureProvider.autoDispose<List<MonthlyStats>>((ref) {
  return ref.watch(dashboardRepositoryProvider).monthly();
});

final topProductsProvider =
    FutureProvider.autoDispose<List<TopProductStats>>((ref) {
  return ref.watch(dashboardRepositoryProvider).topProducts();
});

class DashboardRepository {
  const DashboardRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<LiveStats> liveStats() async {
    final response = await _apiClient.get(ApiEndpoints.adminStatsLive);
    return LiveStats.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StatsSummary> summary() async {
    final response = await _apiClient.get(ApiEndpoints.adminStatsSummary);
    return StatsSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<DailyStats>> daily() async {
    final response = await _apiClient.get(ApiEndpoints.adminStatsDaily);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map((value) => DailyStats.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<List<MonthlyStats>> monthly() async {
    final response = await _apiClient.get(ApiEndpoints.adminStatsMonthly);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map((value) => MonthlyStats.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<List<TopProductStats>> topProducts({
    int days = 7,
    int limit = 8,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.adminStatsTopProducts,
      queryParameters: {'days': days, 'limit': limit},
    );
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => TopProductStats.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
  }
}

class LiveStats {
  const LiveStats({
    required this.ordersLast24h,
    required this.revenueLast24h,
    required this.avgOrderValue24h,
    required this.pendingOrders,
    this.computedAt,
  });

  final int ordersLast24h;
  final double revenueLast24h;
  final double avgOrderValue24h;
  final int pendingOrders;
  final DateTime? computedAt;

  factory LiveStats.fromJson(Map<String, dynamic> json) {
    return LiveStats(
      ordersLast24h: readInt(json['orders_last_24h']),
      revenueLast24h: readDouble(json['revenue_last_24h']),
      avgOrderValue24h: readDouble(json['avg_order_value_24h']),
      pendingOrders: readInt(json['pending_orders']),
      computedAt: readDateTime(json['computed_at']),
    );
  }
}

class StatsSummary {
  const StatsSummary({
    required this.live,
    this.lastDayRevenue,
    this.lastDayOrders,
    this.lastDayAvgBasket,
  });

  final LiveStats live;
  final double? lastDayRevenue;
  final int? lastDayOrders;
  final double? lastDayAvgBasket;

  factory StatsSummary.fromJson(Map<String, dynamic> json) {
    final lastDay = readMap(json['last_day']);
    return StatsSummary(
      live: LiveStats.fromJson(readMap(json['live'])),
      lastDayRevenue: lastDay.isEmpty ? null : readDouble(lastDay['revenue']),
      lastDayOrders: lastDay.isEmpty ? null : readInt(lastDay['order_count']),
      lastDayAvgBasket:
          lastDay.isEmpty ? null : readDouble(lastDay['avg_basket']),
    );
  }
}

class DailyStats {
  const DailyStats({
    required this.date,
    required this.revenue,
    required this.orderCount,
    required this.avgBasket,
  });

  final String date;
  final double revenue;
  final int orderCount;
  final double avgBasket;

  factory DailyStats.fromJson(Map<String, dynamic> json) {
    return DailyStats(
      date: json['date']?.toString() ?? '',
      revenue: readDouble(json['revenue']),
      orderCount: readInt(json['order_count']),
      avgBasket: readDouble(json['avg_basket']),
    );
  }
}

class MonthlyStats {
  const MonthlyStats({
    required this.year,
    required this.month,
    required this.totalOrders,
    required this.totalRevenue,
    required this.avgOrderValue,
  });

  final String year;
  final String month;
  final int totalOrders;
  final double totalRevenue;
  final double avgOrderValue;

  factory MonthlyStats.fromJson(Map<String, dynamic> json) {
    return MonthlyStats(
      year: json['year']?.toString() ?? '',
      month: json['month']?.toString() ?? '',
      totalOrders: readInt(json['total_orders']),
      totalRevenue: readDouble(json['total_revenue']),
      avgOrderValue: readDouble(json['avg_order_value']),
    );
  }
}

class TopProductStats {
  const TopProductStats({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.revenue,
  });

  final int productId;
  final String productName;
  final int quantity;
  final double revenue;

  factory TopProductStats.fromJson(Map<String, dynamic> json) {
    return TopProductStats(
      productId: readInt(json['product_id']),
      productName: json['product_name']?.toString() ?? '',
      quantity: readInt(json['quantity']),
      revenue: readDouble(json['revenue']),
    );
  }
}
