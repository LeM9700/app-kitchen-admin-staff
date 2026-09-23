import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/paginated.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  return CustomersRepository(ref.watch(apiClientProvider));
});

final adminCustomersProvider = FutureProvider.autoDispose
    .family<PaginatedResult<CustomerListItem>, CustomersQuery>((ref, query) {
  return ref.watch(customersRepositoryProvider).listCustomers(query);
});

final customerDetailProvider =
    FutureProvider.autoDispose.family<CustomerDetail, int>((ref, customerId) {
  return ref.watch(customersRepositoryProvider).customerDetail(customerId);
});

final customerCommunicationsProvider = FutureProvider.autoDispose
    .family<PaginatedResult<CustomerCommunication>, int>((ref, customerId) {
  return ref
      .watch(customersRepositoryProvider)
      .customerCommunications(customerId);
});

final customerMessageTemplatesProvider =
    FutureProvider.autoDispose<List<CustomerMessageTemplate>>((ref) {
  return ref.watch(customersRepositoryProvider).messageTemplates();
});

class CustomersRepository {
  const CustomersRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<PaginatedResult<CustomerListItem>> listCustomers(
    CustomersQuery query,
  ) async {
    final response = await _apiClient.get(
      ApiEndpoints.adminCustomers,
      queryParameters: query.toQueryParameters(),
    );
    return PaginatedResult<CustomerListItem>.fromJson(
      Map<String, dynamic>.from(response.data as Map),
      CustomerListItem.fromJson,
    );
  }

  Future<CustomerDetail> customerDetail(int customerId) async {
    final response = await _apiClient.get(
      ApiEndpoints.adminCustomer(customerId),
      queryParameters: const {'page': 1, 'page_size': 50},
    );
    return CustomerDetail.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<CustomerOrderDetail> customerOrderDetail({
    required int customerId,
    required int orderId,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.adminCustomerOrder(customerId, orderId),
    );
    return CustomerOrderDetail.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<PaginatedResult<CustomerCommunication>> customerCommunications(
    int customerId,
  ) async {
    final response = await _apiClient.get(
      ApiEndpoints.adminCustomerCommunications(customerId),
      queryParameters: const {'page': 1, 'page_size': 100},
    );
    return PaginatedResult<CustomerCommunication>.fromJson(
      Map<String, dynamic>.from(response.data as Map),
      CustomerCommunication.fromJson,
    );
  }

  Future<List<CustomerMessageTemplate>> messageTemplates() async {
    final response = await _apiClient.get(
      ApiEndpoints.adminCustomerMessageTemplates,
    );
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => CustomerMessageTemplate.fromJson(
            Map<String, dynamic>.from(value),
          ),
        )
        .toList();
  }

  Future<CustomerMessageSendResult> sendCustomerMessage({
    required int customerId,
    required CustomerMessageDraft draft,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.adminCustomerCommunications(customerId),
      data: draft.toJson(),
    );
    return CustomerMessageSendResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<CustomerMessageSendResult> sendBulkMessage(
    CustomerBulkMessageDraft draft,
  ) async {
    final response = await _apiClient.post(
      ApiEndpoints.adminCustomersBulkMessages,
      data: draft.toJson(),
    );
    return CustomerMessageSendResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<String> exportCsv(CustomersQuery query) {
    return _apiClient.getText(
      ApiEndpoints.adminCustomersExportCsv,
      queryParameters: query.toQueryParameters(includePagination: false),
    );
  }
}

class CustomersQuery {
  const CustomersQuery({
    this.query,
    this.isActive,
    this.emailVerified,
    this.marketingEmailOptIn,
    this.marketingPushOptIn,
    this.page = 1,
    this.pageSize = 50,
  });

  final String? query;
  final bool? isActive;
  final bool? emailVerified;
  final bool? marketingEmailOptIn;
  final bool? marketingPushOptIn;
  final int page;
  final int pageSize;

  Map<String, dynamic> toQueryParameters({bool includePagination = true}) {
    return {
      if (query != null && query!.trim().isNotEmpty) 'query': query!.trim(),
      if (isActive != null) 'is_active': isActive,
      if (emailVerified != null) 'email_verified': emailVerified,
      if (marketingEmailOptIn != null)
        'marketing_email_opt_in': marketingEmailOptIn,
      if (marketingPushOptIn != null)
        'marketing_push_opt_in': marketingPushOptIn,
      if (includePagination) 'page': page,
      if (includePagination) 'page_size': pageSize,
    };
  }

  CustomersQuery copyWith({
    String? query,
    bool clearQuery = false,
    bool? isActive,
    bool clearIsActive = false,
    bool? emailVerified,
    bool clearEmailVerified = false,
    bool? marketingEmailOptIn,
    bool clearMarketingEmailOptIn = false,
    bool? marketingPushOptIn,
    bool clearMarketingPushOptIn = false,
    int? page,
    int? pageSize,
  }) {
    return CustomersQuery(
      query: clearQuery ? null : query ?? this.query,
      isActive: clearIsActive ? null : isActive ?? this.isActive,
      emailVerified:
          clearEmailVerified ? null : emailVerified ?? this.emailVerified,
      marketingEmailOptIn: clearMarketingEmailOptIn
          ? null
          : marketingEmailOptIn ?? this.marketingEmailOptIn,
      marketingPushOptIn: clearMarketingPushOptIn
          ? null
          : marketingPushOptIn ?? this.marketingPushOptIn,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CustomersQuery &&
        other.query == query &&
        other.isActive == isActive &&
        other.emailVerified == emailVerified &&
        other.marketingEmailOptIn == marketingEmailOptIn &&
        other.marketingPushOptIn == marketingPushOptIn &&
        other.page == page &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode {
    return Object.hash(
      query,
      isActive,
      emailVerified,
      marketingEmailOptIn,
      marketingPushOptIn,
      page,
      pageSize,
    );
  }
}

class CustomerListItem {
  const CustomerListItem({
    required this.id,
    required this.email,
    required this.isActive,
    required this.emailVerified,
    required this.marketingEmailOptIn,
    required this.marketingPushOptIn,
    required this.orderCount,
    required this.totalSpent,
    required this.loyaltyPoints,
    this.fullName,
    this.phone,
    this.lastOrderAt,
    this.createdAt,
  });

  final int id;
  final String email;
  final String? fullName;
  final String? phone;
  final bool isActive;
  final bool emailVerified;
  final bool marketingEmailOptIn;
  final bool marketingPushOptIn;
  final int orderCount;
  final double totalSpent;
  final DateTime? lastOrderAt;
  final int loyaltyPoints;
  final DateTime? createdAt;

  String get displayName {
    final name = fullName?.trim();
    return name == null || name.isEmpty ? email : name;
  }

  factory CustomerListItem.fromJson(Map<String, dynamic> json) {
    return CustomerListItem(
      id: readInt(json['id']),
      email: json['email']?.toString() ?? '',
      fullName: json['full_name']?.toString(),
      phone: json['phone']?.toString(),
      isActive: readBool(json['is_active']),
      emailVerified: readBool(json['email_verified']),
      marketingEmailOptIn: readBool(json['marketing_email_opt_in']),
      marketingPushOptIn: readBool(json['marketing_push_opt_in']),
      orderCount: readInt(json['order_count']),
      totalSpent: readDouble(json['total_spent']),
      lastOrderAt: readDateTime(json['last_order_at'])?.toLocal(),
      loyaltyPoints: readInt(json['loyalty_points']),
      createdAt: readDateTime(json['created_at'])?.toLocal(),
    );
  }
}

class CustomerDetail extends CustomerListItem {
  const CustomerDetail({
    required super.id,
    required super.email,
    required super.isActive,
    required super.emailVerified,
    required super.marketingEmailOptIn,
    required super.marketingPushOptIn,
    required super.orderCount,
    required super.totalSpent,
    required super.loyaltyPoints,
    required this.orders,
    super.fullName,
    super.phone,
    super.lastOrderAt,
    super.createdAt,
  });

  final List<OrderSummary> orders;

  factory CustomerDetail.fromJson(Map<String, dynamic> json) {
    final item = CustomerListItem.fromJson(json);
    return CustomerDetail(
      id: item.id,
      email: item.email,
      fullName: item.fullName,
      phone: item.phone,
      isActive: item.isActive,
      emailVerified: item.emailVerified,
      marketingEmailOptIn: item.marketingEmailOptIn,
      marketingPushOptIn: item.marketingPushOptIn,
      orderCount: item.orderCount,
      totalSpent: item.totalSpent,
      lastOrderAt: item.lastOrderAt,
      loyaltyPoints: item.loyaltyPoints,
      createdAt: item.createdAt,
      orders: (json['orders'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => OrderSummary.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList(),
    );
  }
}

class CustomerOrderDetail {
  const CustomerOrderDetail({
    required this.order,
    this.payment,
  });

  final OrderDetail order;
  final PaymentDetail? payment;

  factory CustomerOrderDetail.fromJson(Map<String, dynamic> json) {
    final paymentJson = json['payment'];
    return CustomerOrderDetail(
      order: OrderDetail.fromJson(readMap(json['order'])),
      payment: paymentJson == null
          ? null
          : PaymentDetail.fromJson(readMap(paymentJson)),
    );
  }
}

class CustomerCommunication {
  const CustomerCommunication({
    required this.id,
    required this.userId,
    required this.channel,
    required this.messageType,
    required this.body,
    required this.status,
    this.templateKey,
    this.subject,
    this.error,
    this.sentByUserId,
    this.createdAt,
    this.sentAt,
  });

  final int id;
  final int userId;
  final String channel;
  final String messageType;
  final String? templateKey;
  final String? subject;
  final String body;
  final String status;
  final String? error;
  final int? sentByUserId;
  final DateTime? createdAt;
  final DateTime? sentAt;

  factory CustomerCommunication.fromJson(Map<String, dynamic> json) {
    return CustomerCommunication(
      id: readInt(json['id']),
      userId: readInt(json['user_id']),
      channel: json['channel']?.toString() ?? 'push',
      messageType: json['message_type']?.toString() ?? 'transactional',
      templateKey: json['template_key']?.toString(),
      subject: json['subject']?.toString(),
      body: json['body']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      error: json['error']?.toString(),
      sentByUserId: json['sent_by_user_id'] == null
          ? null
          : readInt(json['sent_by_user_id']),
      createdAt: readDateTime(json['created_at'])?.toLocal(),
      sentAt: readDateTime(json['sent_at'])?.toLocal(),
    );
  }
}

class CustomerMessageTemplate {
  const CustomerMessageTemplate({
    required this.key,
    required this.label,
    required this.messageType,
    required this.channels,
    required this.body,
    this.subject,
  });

  final String key;
  final String label;
  final String messageType;
  final List<String> channels;
  final String? subject;
  final String body;

  factory CustomerMessageTemplate.fromJson(Map<String, dynamic> json) {
    return CustomerMessageTemplate(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      messageType: json['message_type']?.toString() ?? 'transactional',
      channels: (json['channels'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      subject: json['subject']?.toString(),
      body: json['body']?.toString() ?? '',
    );
  }
}

class CustomerMessageDraft {
  const CustomerMessageDraft({
    required this.channels,
    required this.messageType,
    this.templateKey,
    this.subject,
    this.body,
  });

  final List<String> channels;
  final String messageType;
  final String? templateKey;
  final String? subject;
  final String? body;

  Map<String, dynamic> toJson() {
    return {
      'channels': channels,
      'message_type': messageType,
      if (templateKey != null && templateKey!.isNotEmpty)
        'template_key': templateKey,
      if (subject != null && subject!.trim().isNotEmpty)
        'subject': subject!.trim(),
      if (body != null && body!.trim().isNotEmpty) 'body': body!.trim(),
    };
  }
}

class CustomerBulkMessageDraft extends CustomerMessageDraft {
  const CustomerBulkMessageDraft({
    required super.channels,
    required super.messageType,
    required this.confirmBulkSend,
    this.customerIds,
    this.query,
    this.isActive,
    this.emailVerified,
    this.marketingEmailOptIn,
    this.marketingPushOptIn,
    super.templateKey,
    super.subject,
    super.body,
  });

  final List<int>? customerIds;
  final String? query;
  final bool? isActive;
  final bool? emailVerified;
  final bool? marketingEmailOptIn;
  final bool? marketingPushOptIn;
  final bool confirmBulkSend;

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      if (customerIds != null && customerIds!.isNotEmpty)
        'customer_ids': customerIds,
      if (query != null && query!.trim().isNotEmpty) 'query': query!.trim(),
      if (isActive != null) 'is_active': isActive,
      if (emailVerified != null) 'email_verified': emailVerified,
      if (marketingEmailOptIn != null)
        'marketing_email_opt_in': marketingEmailOptIn,
      if (marketingPushOptIn != null)
        'marketing_push_opt_in': marketingPushOptIn,
      'confirm_bulk_send': confirmBulkSend,
    };
  }
}

class CustomerMessageSendResult {
  const CustomerMessageSendResult({
    required this.created,
    required this.skipped,
    required this.communicationIds,
  });

  final int created;
  final int skipped;
  final List<int> communicationIds;

  factory CustomerMessageSendResult.fromJson(Map<String, dynamic> json) {
    return CustomerMessageSendResult(
      created: readInt(json['created']),
      skipped: readInt(json['skipped']),
      communicationIds: (json['communication_ids'] as List? ?? const [])
          .map(readInt)
          .toList(),
    );
  }
}
