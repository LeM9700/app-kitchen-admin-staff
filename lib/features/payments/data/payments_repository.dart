import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/paginated.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  return PaymentsRepository(ref.watch(apiClientProvider));
});

final paymentsSummaryProvider =
    FutureProvider.autoDispose<PaymentSummary>((ref) {
  return ref.watch(paymentsRepositoryProvider).summary();
});

final paymentStatusFilterProvider = StateProvider<String?>((ref) => null);

final paymentsProvider =
    FutureProvider.autoDispose<List<PaymentListItem>>((ref) {
  final status = ref.watch(paymentStatusFilterProvider);
  return ref.watch(paymentsRepositoryProvider).listPayments(
        pageSize: 50,
        status: status,
      );
});

final terminalReadersProvider =
    FutureProvider.autoDispose<List<TerminalReader>>((ref) {
  return ref.watch(paymentsRepositoryProvider).listTerminalReaders();
});

final connectStatusProvider = FutureProvider.autoDispose<ConnectStatus>((ref) {
  return ref.watch(paymentsRepositoryProvider).connectStatus();
});

class PaymentsRepository {
  const PaymentsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<PaymentSummary> summary() async {
    final response = await _apiClient.get(ApiEndpoints.paymentSummary);
    return PaymentSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<PaymentListItem>> listPayments({
    int page = 1,
    int pageSize = 50,
    String? status,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.payments,
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final result = PaginatedResult.fromJson(
      response.data as Map<String, dynamic>,
      PaymentListItem.fromJson,
    );
    return result.items;
  }

  Future<PaymentDetail> detail(int orderId) async {
    final response = await _apiClient.get(ApiEndpoints.paymentDetail(orderId));
    return PaymentDetail.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Refund> refund({
    required int orderId,
    int? amountCents,
    required String reason,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.paymentRefund(orderId),
      data: {
        if (amountCents != null) 'amount': amountCents,
        'reason': reason,
      },
    );
    return Refund.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<TerminalReader>> listTerminalReaders() async {
    final response = await _apiClient.get(ApiEndpoints.terminalReaders);
    final data = readMap(response.data);
    return (data['readers'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => TerminalReader.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
  }

  Future<TerminalIntent> createTerminalIntent({
    required int orderId,
    String? readerId,
    bool processOnReader = false,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.terminalIntent,
      data: {
        'order_id': orderId,
        if (readerId != null && readerId.trim().isNotEmpty)
          'reader_id': readerId.trim(),
        'process_on_reader': processOnReader,
      },
    );
    return TerminalIntent.fromJson(response.data as Map<String, dynamic>);
  }

  Future<String> exportCsv() {
    return _apiClient.getText(ApiEndpoints.paymentsExportCsv);
  }

  Future<ConnectStatus> connectStatus() async {
    final response = await _apiClient.get(ApiEndpoints.connectStatus);
    return ConnectStatus.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ConnectOnboarding> startConnectOnboarding({
    required String returnUrl,
    required String refreshUrl,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.connectOnboarding,
      data: {
        'return_url': returnUrl,
        'refresh_url': refreshUrl,
      },
    );
    return ConnectOnboarding.fromJson(response.data as Map<String, dynamic>);
  }

  Future<String> connectDashboardUrl() async {
    final response = await _apiClient.get(ApiEndpoints.connectDashboard);
    final data = readMap(response.data);
    return data['url']?.toString() ?? '';
  }
}

class PaymentListItem {
  const PaymentListItem({
    required this.id,
    required this.orderId,
    required this.provider,
    required this.amount,
    required this.currency,
    required this.status,
    required this.refundedAmountCents,
    this.providerPaymentId,
    this.externalReference,
    this.amountReceived,
    this.createdByUserId,
    this.createdAt,
  });

  final int id;
  final int orderId;
  final String provider;
  final String? providerPaymentId;
  final String? externalReference;
  final double amount;
  final double? amountReceived;
  final String currency;
  final String status;
  final int? createdByUserId;
  final DateTime? createdAt;
  final int refundedAmountCents;

  factory PaymentListItem.fromJson(Map<String, dynamic> json) {
    return PaymentListItem(
      id: readInt(json['id']),
      orderId: readInt(json['order_id']),
      provider: json['provider']?.toString() ?? '',
      providerPaymentId: json['provider_payment_id']?.toString(),
      externalReference: json['external_reference']?.toString(),
      amount: readDouble(json['amount']),
      amountReceived: json['amount_received'] == null
          ? null
          : readDouble(json['amount_received']),
      currency: json['currency']?.toString() ?? 'eur',
      status: json['status']?.toString() ?? 'pending',
      createdByUserId: json['created_by_user_id'] == null
          ? null
          : readInt(json['created_by_user_id']),
      createdAt: readDateTime(json['created_at']),
      refundedAmountCents: readInt(json['refunded_amount_cents']),
    );
  }
}

class PaymentSummary {
  const PaymentSummary({
    required this.collectedAmountCents,
    required this.refundedAmountCents,
    required this.netAmountCents,
    required this.paymentCount,
    required this.refundCount,
    required this.countsByStatus,
  });

  final int collectedAmountCents;
  final int refundedAmountCents;
  final int netAmountCents;
  final int paymentCount;
  final int refundCount;
  final Map<String, int> countsByStatus;

  factory PaymentSummary.fromJson(Map<String, dynamic> json) {
    final counts = readMap(json['counts_by_status']);
    return PaymentSummary(
      collectedAmountCents: readInt(json['collected_amount_cents']),
      refundedAmountCents: readInt(json['refunded_amount_cents']),
      netAmountCents: readInt(json['net_amount_cents']),
      paymentCount: readInt(json['payment_count']),
      refundCount: readInt(json['refund_count']),
      countsByStatus: counts.map(
        (key, value) => MapEntry(key, readInt(value)),
      ),
    );
  }
}

class Refund {
  const Refund({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.reason,
    this.failureReason,
    this.createdByUserId,
  });

  final int id;
  final int orderId;
  final int amount;
  final String status;
  final DateTime? createdAt;
  final String? reason;
  final String? failureReason;
  final int? createdByUserId;

  factory Refund.fromJson(Map<String, dynamic> json) {
    return Refund(
      id: readInt(json['id']),
      orderId: readInt(json['order_id']),
      amount: readInt(json['amount']),
      status: json['status']?.toString() ?? 'pending',
      createdAt: readDateTime(json['created_at']),
      reason: json['reason']?.toString(),
      failureReason: json['failure_reason']?.toString(),
      createdByUserId: json['created_by_user_id'] == null
          ? null
          : readInt(json['created_by_user_id']),
    );
  }
}

class PaymentDetail {
  const PaymentDetail({
    required this.orderId,
    required this.payment,
    required this.paidAmountCents,
    required this.refundedAmountCents,
    required this.remainingRefundableCents,
    required this.refunds,
    this.receiptUrl,
  });

  final int orderId;
  final PaymentListItem payment;
  final int paidAmountCents;
  final int refundedAmountCents;
  final int remainingRefundableCents;
  final List<Refund> refunds;
  final String? receiptUrl;

  factory PaymentDetail.fromJson(Map<String, dynamic> json) {
    return PaymentDetail(
      orderId: readInt(json['order_id']),
      payment: PaymentListItem.fromJson(readMap(json['payment'])),
      paidAmountCents: readInt(json['paid_amount_cents']),
      refundedAmountCents: readInt(json['refunded_amount_cents']),
      remainingRefundableCents: readInt(json['remaining_refundable_cents']),
      refunds: (json['refunds'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => Refund.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
      receiptUrl: json['receipt_url']?.toString(),
    );
  }
}

class TerminalReader {
  const TerminalReader({
    required this.id,
    required this.label,
    required this.status,
    required this.raw,
  });

  final String id;
  final String label;
  final String status;
  final Map<String, dynamic> raw;

  factory TerminalReader.fromJson(Map<String, dynamic> json) {
    return TerminalReader(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? json['id']?.toString() ?? 'Reader',
      status: json['status']?.toString() ?? 'unknown',
      raw: json,
    );
  }
}

class TerminalIntent {
  const TerminalIntent({
    required this.payment,
    this.clientSecret,
    this.readerAction,
  });

  final String? clientSecret;
  final PaymentListItem payment;
  final Map<String, dynamic>? readerAction;

  factory TerminalIntent.fromJson(Map<String, dynamic> json) {
    return TerminalIntent(
      clientSecret: json['client_secret']?.toString(),
      payment: PaymentListItem.fromJson(readMap(json['payment'])),
      readerAction:
          json['reader_action'] == null ? null : readMap(json['reader_action']),
    );
  }
}

class ConnectStatus {
  const ConnectStatus({
    required this.detailsSubmitted,
    required this.payoutsEnabled,
    required this.chargesEnabled,
    required this.onboardingComplete,
    this.stripeAccountId,
  });

  final String? stripeAccountId;
  final bool detailsSubmitted;
  final bool payoutsEnabled;
  final bool chargesEnabled;
  final bool onboardingComplete;

  factory ConnectStatus.fromJson(Map<String, dynamic> json) {
    return ConnectStatus(
      stripeAccountId: json['stripe_account_id']?.toString(),
      detailsSubmitted: readBool(json['details_submitted']),
      payoutsEnabled: readBool(json['payouts_enabled']),
      chargesEnabled: readBool(json['charges_enabled']),
      onboardingComplete: readBool(json['onboarding_complete']),
    );
  }
}

class ConnectOnboarding {
  const ConnectOnboarding({
    required this.url,
    required this.stripeAccountId,
  });

  final String url;
  final String stripeAccountId;

  factory ConnectOnboarding.fromJson(Map<String, dynamic> json) {
    return ConnectOnboarding(
      url: json['url']?.toString() ?? '',
      stripeAccountId: json['stripe_account_id']?.toString() ?? '',
    );
  }
}
