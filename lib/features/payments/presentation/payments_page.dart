import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/config/stripe_connect_callbacks.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/cards/stat_card.dart';
import 'package:app_admin_staff/design_system/components/forms/pill_filter_bar.dart';
import 'package:app_admin_staff/design_system/tokens/app_breakpoints.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentsPage extends ConsumerStatefulWidget {
  const PaymentsPage({super.key});

  @override
  ConsumerState<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends ConsumerState<PaymentsPage> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(paymentsSummaryProvider);
    final payments = ref.watch(paymentsProvider);
    final statusFilter = ref.watch(paymentStatusFilterProvider);
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    final permissions = PermissionSet(
      role: user?.role ?? 'staff',
      permissions: user?.permissions,
    );
    final canRefund = user?.role == 'admin' || user?.role == 'super-admin';
    final canUseTerminal = permissions.can(AppPermission.paymentsTerminal);
    final readers = canUseTerminal
        ? ref.watch(terminalReadersProvider)
        : const AsyncValue<List<TerminalReader>>.data([]);
    final connect = canRefund ? ref.watch(connectStatusProvider) : null;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(paymentsSummaryProvider);
        ref.invalidate(paymentsProvider);
        ref.invalidate(terminalReadersProvider);
        ref.invalidate(connectStatusProvider);
        await Future.wait([
          ref.read(paymentsSummaryProvider.future),
          ref.read(paymentsProvider.future),
        ]);
      },
      child: ListView(
        padding: EdgeInsets.all(
          AppBreakpoints.isMobile(context) ? AppSpacing.md : AppSpacing.xxl,
        ),
        children: [
          _PaymentsHeader(
            canExport: canRefund,
            onExport: () => _exportCsv(context, ref),
            onRefresh: () {
              ref.invalidate(paymentsSummaryProvider);
              ref.invalidate(paymentsProvider);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          summary.when(
            data: (value) => _PaymentsStats(summary: value),
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
          const SizedBox(height: AppSpacing.lg),
          _PaymentsToolbar(
            controller: _searchController,
            status: statusFilter,
            onSearchChanged: (value) => setState(() => _search = value),
            onStatusChanged: (value) {
              ref.read(paymentStatusFilterProvider.notifier).state = value;
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          if (canRefund) ...[
            connect?.when(
                  data: (value) => DsCard(child: _ConnectPanel(status: value)),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stackTrace) => Text(error.toString()),
                ) ??
                const SizedBox.shrink(),
            const SizedBox(height: AppSpacing.md),
          ],
          if (canUseTerminal) ...[
            readers.when(
              data: (items) => DsCard(child: _TerminalPanel(readers: items)),
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => Text(error.toString()),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          payments.when(
            data: (items) {
              final filtered = _filterPayments(items, _search);
              return _PaymentsTable(
                payments: filtered,
                canRefund: canRefund,
                onDetail: (payment) => _detail(context, ref, payment),
                onRefund: (payment) => _refund(context, ref, payment),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
        ],
      ),
    );
  }

  List<PaymentListItem> _filterPayments(
    List<PaymentListItem> payments,
    String query,
  ) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return payments;
    }
    return payments.where((payment) {
      return payment.orderId.toString().contains(trimmed) ||
          payment.provider.toLowerCase().contains(trimmed) ||
          payment.status.toLowerCase().contains(trimmed) ||
          (payment.externalReference ?? '').toLowerCase().contains(trimmed);
    }).toList();
  }

  Future<void> _refund(
    BuildContext context,
    WidgetRef ref,
    PaymentListItem payment,
  ) async {
    PaymentDetail detail;
    try {
      detail =
          await ref.read(paymentsRepositoryProvider).detail(payment.orderId);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    var fullRefund = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Remboursement #${payment.orderId}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _MoneyTile(
                      label: 'Paye',
                      value: formatCents(detail.paidAmountCents),
                    ),
                    _MoneyTile(
                      label: 'Remboursable',
                      value: formatCents(detail.remainingRefundableCents),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.undo_outlined),
                      label: Text('Total'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.tune_outlined),
                      label: Text('Partiel'),
                    ),
                  ],
                  selected: {fullRefund},
                  onSelectionChanged: (value) {
                    setState(() => fullRefund = value.first);
                  },
                ),
                if (!fullRefund) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Montant EUR',
                      prefixIcon: Icon(Icons.euro_outlined),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Raison obligatoire',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: detail.remainingRefundableCents <= 0
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Rembourser'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    if (reasonController.text.trim().isEmpty) {
      _snack(context, 'Raison obligatoire');
      return;
    }
    int? amountCents;
    if (!fullRefund) {
      final amount =
          double.tryParse(amountController.text.trim().replaceAll(',', '.'));
      amountCents = amount == null ? null : (amount * 100).round();
      if (amountCents == null || amountCents <= 0) {
        _snack(context, 'Montant invalide');
        return;
      }
      if (amountCents > detail.remainingRefundableCents) {
        _snack(context, 'Montant superieur au remboursable');
        return;
      }
    }
    try {
      await ref.read(paymentsRepositoryProvider).refund(
            orderId: payment.orderId,
            amountCents: amountCents,
            reason: reasonController.text.trim(),
          );
      ref.invalidate(paymentsSummaryProvider);
      ref.invalidate(paymentsProvider);
      if (context.mounted) {
        _snack(context, 'Remboursement envoye');
      }
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _detail(
    BuildContext context,
    WidgetRef ref,
    PaymentListItem payment,
  ) async {
    try {
      final detail =
          await ref.read(paymentsRepositoryProvider).detail(payment.orderId);
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Paiement #${detail.orderId}'),
          content: SizedBox(
            width: 620,
            child: ListView(
              shrinkWrap: true,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MoneyTile(
                      label: 'Paye',
                      value: formatCents(detail.paidAmountCents),
                    ),
                    _MoneyTile(
                      label: 'Rembourse',
                      value: formatCents(detail.refundedAmountCents),
                    ),
                    _MoneyTile(
                      label: 'Remboursable',
                      value: formatCents(detail.remainingRefundableCents),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(detail.payment.provider),
                  subtitle: Text(
                    [
                      humanStatus(detail.payment.status),
                      if (detail.payment.externalReference != null)
                        detail.payment.externalReference!,
                      if (detail.receiptUrl != null) detail.receiptUrl!,
                    ].join(' - '),
                  ),
                ),
                Text(
                  'Remboursements',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (detail.refunds.isEmpty)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('Aucun remboursement'),
                  )
                else
                  ...detail.refunds.map((refund) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.undo_outlined),
                      title: Text(formatCents(refund.amount)),
                      subtitle: Text(refund.reason ?? '-'),
                      trailing: Text(humanStatus(refund.status)),
                    );
                  }),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final csv = await ref.read(paymentsRepositoryProvider).exportCsv();
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export paiements CSV'),
          content: SizedBox(width: 720, child: SelectableText(csv)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _snack(context, error.toString());
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PaymentsHeader extends StatelessWidget {
  const _PaymentsHeader({
    required this.canExport,
    required this.onExport,
    required this.onRefresh,
  });

  final bool canExport;
  final VoidCallback onExport;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Encaissements',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Paiements, statuts provider et remboursements',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            if (canExport)
              IconButton.filledTonal(
                tooltip: 'Export CSV',
                onPressed: onExport,
                icon: const Icon(Icons.download_outlined),
              ),
            IconButton.filledTonal(
              tooltip: 'Rafraichir',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
  }
}

class _PaymentsStats extends StatelessWidget {
  const _PaymentsStats({required this.summary});

  final PaymentSummary summary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        AppStatCard(
          label: 'Collecte',
          value: formatCents(summary.collectedAmountCents),
          subtitle: '${summary.paymentCount} paiement(s)',
          icon: Icons.payments_outlined,
          accentColor: AppColors.success,
        ),
        AppStatCard(
          label: 'Rembourse',
          value: formatCents(summary.refundedAmountCents),
          subtitle: '${summary.refundCount} refund(s)',
          icon: Icons.undo_outlined,
          accentColor: AppColors.warning,
        ),
        AppStatCard(
          label: 'Net',
          value: formatCents(summary.netAmountCents),
          subtitle: 'Collecte moins remboursements',
          icon: Icons.account_balance_wallet_outlined,
          accentColor: AppColors.infoAlt,
        ),
        AppStatCard(
          label: 'Statuts',
          value: summary.countsByStatus.length.toString(),
          subtitle: summary.countsByStatus.entries
              .take(2)
              .map((entry) => '${entry.key}:${entry.value}')
              .join(' '),
          icon: Icons.query_stats_outlined,
          accentColor: AppColors.accent,
        ),
      ],
    );
  }
}

class _PaymentsToolbar extends StatelessWidget {
  const _PaymentsToolbar({
    required this.controller,
    required this.status,
    required this.onSearchChanged,
    required this.onStatusChanged,
  });

  final TextEditingController controller;
  final String? status;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 340,
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Commande, provider, reference',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          PillFilterBar<String?>(
            selected: status,
            onSelected: onStatusChanged,
            options: const [
              PillFilterOption<String?>(
                value: null,
                label: 'Tous',
                icon: Icons.receipt_long_outlined,
              ),
              PillFilterOption<String?>(
                value: 'paid',
                label: 'Payes',
                icon: Icons.check_circle_outline,
              ),
              PillFilterOption<String?>(
                value: 'refunded',
                label: 'Refunded',
                icon: Icons.undo_outlined,
              ),
              PillFilterOption<String?>(
                value: 'partially_refunded',
                label: 'Partiels',
                icon: Icons.tune_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentsTable extends StatelessWidget {
  const _PaymentsTable({
    required this.payments,
    required this.canRefund,
    required this.onDetail,
    required this.onRefund,
  });

  final List<PaymentListItem> payments;
  final bool canRefund;
  final ValueChanged<PaymentListItem> onDetail;
  final ValueChanged<PaymentListItem> onRefund;

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return const DsCard(
        child: EmptyState(
          icon: Icons.payments_outlined,
          title: 'Aucun paiement',
        ),
      );
    }
    return DsCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth < 1040 ? 1040.0 : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  const _PaymentsTableHeader(),
                  const Divider(height: 1),
                  for (final payment in payments) ...[
                    _PaymentsTableRow(
                      payment: payment,
                      canRefund: canRefund,
                      onDetail: onDetail,
                      onRefund: onRefund,
                    ),
                    const Divider(height: 1),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PaymentsTableHeader extends StatelessWidget {
  const _PaymentsTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: const Row(
        children: [
          _PaymentTableLabel('Commande', width: 120),
          _PaymentTableLabel('Provider', width: 160),
          _PaymentTableLabel('Montant', width: 120),
          _PaymentTableLabel('Rembourse', width: 120),
          _PaymentTableLabel('Statut', width: 170),
          _PaymentTableLabel('Date', width: 190),
          Expanded(child: _PaymentTableLabel('Actions')),
        ],
      ),
    );
  }
}

class _PaymentsTableRow extends StatelessWidget {
  const _PaymentsTableRow({
    required this.payment,
    required this.canRefund,
    required this.onDetail,
    required this.onRefund,
  });

  final PaymentListItem payment;
  final bool canRefund;
  final ValueChanged<PaymentListItem> onDetail;
  final ValueChanged<PaymentListItem> onRefund;

  @override
  Widget build(BuildContext context) {
    final refundable =
        canRefund && {'paid', 'partially_refunded'}.contains(payment.status);
    return InkWell(
      onTap: () => onDetail(payment),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(width: 120, child: Text('#${payment.orderId}')),
            SizedBox(
              width: 160,
              child: Text(
                payment.provider,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: 120, child: Text(formatMoney(payment.amount))),
            SizedBox(
              width: 120,
              child: Text(formatCents(payment.refundedAmountCents)),
            ),
            SizedBox(
              width: 170,
              child: StatusBadge(
                label: humanStatus(payment.status),
                tone: _paymentTone(payment.status),
                compact: true,
              ),
            ),
            SizedBox(
              width: 190,
              child: Text(formatDateTime(payment.createdAt)),
            ),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                children: [
                  IconButton(
                    tooltip: 'Detail',
                    onPressed: () => onDetail(payment),
                    icon: const Icon(Icons.receipt_long_outlined),
                  ),
                  if (refundable)
                    IconButton(
                      tooltip: 'Rembourser',
                      onPressed: () => onRefund(payment),
                      icon: const Icon(Icons.undo_outlined),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  StatusTone _paymentTone(String status) {
    return switch (status) {
      'paid' => StatusTone.success,
      'partially_refunded' => StatusTone.warning,
      'refunded' => StatusTone.neutral,
      'failed' => StatusTone.danger,
      _ => StatusTone.info,
    };
  }
}

class _PaymentTableLabel extends StatelessWidget {
  const _PaymentTableLabel(this.label, {this.width});

  final String label;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
    );
    if (width == null) {
      return text;
    }
    return SizedBox(width: width, child: text);
  }
}

class _ConnectPanel extends ConsumerWidget {
  const _ConnectPanel({required this.status});

  final ConnectStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      leading: Icon(
        status.onboardingComplete
            ? Icons.verified_outlined
            : Icons.pending_actions_outlined,
      ),
      title: Text(
        status.onboardingComplete ? 'Compte operationnel' : 'Onboarding requis',
      ),
      subtitle: Text(status.stripeAccountId ?? 'Aucun compte connecte'),
      trailing: Wrap(
        spacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => _openOnboarding(context, ref),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Onboarding'),
          ),
          FilledButton.icon(
            onPressed: status.detailsSubmitted
                ? () => _openDashboard(context, ref)
                : null,
            icon: const Icon(Icons.dashboard_outlined),
            label: const Text('Dashboard'),
          ),
        ],
      ),
    );
  }

  Future<void> _openOnboarding(BuildContext context, WidgetRef ref) async {
    late final StripeConnectCallbackConfig callbacks;
    try {
      callbacks = StripeConnectCallbackConfig.fromEnvironment().validated();
    } on StateError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      return;
    }

    final response =
        await ref.read(paymentsRepositoryProvider).startConnectOnboarding(
              returnUrl: callbacks.returnUrl,
              refreshUrl: callbacks.refreshUrl,
            );
    if (!context.mounted) {
      return;
    }
    await _openUrl(context, response.url);
    ref.invalidate(connectStatusProvider);
  }

  Future<void> _openDashboard(BuildContext context, WidgetRef ref) async {
    final url =
        await ref.read(paymentsRepositoryProvider).connectDashboardUrl();
    if (!context.mounted) {
      return;
    }
    await _openUrl(context, url);
  }

  Future<void> _openUrl(BuildContext context, String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lien Stripe'),
          content: SelectableText(value),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    }
  }
}

class _TerminalPanel extends ConsumerStatefulWidget {
  const _TerminalPanel({required this.readers});

  final List<TerminalReader> readers;

  @override
  ConsumerState<_TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends ConsumerState<_TerminalPanel> {
  final _orderController = TextEditingController();
  String? _readerId;
  bool _processing = false;

  @override
  void dispose() {
    _orderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 180,
          child: TextField(
            controller: _orderController,
            decoration: const InputDecoration(
              labelText: 'Commande',
              prefixIcon: Icon(Icons.receipt_outlined),
            ),
            keyboardType: TextInputType.number,
          ),
        ),
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<String>(
            initialValue: _readerId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Lecteur',
              prefixIcon: Icon(Icons.credit_card),
            ),
            items: widget.readers
                .map(
                  (reader) => DropdownMenuItem(
                    value: reader.id,
                    child: Text('${reader.label} - ${reader.status}'),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _readerId = value),
          ),
        ),
        FilledButton.icon(
          onPressed: _processing ? null : _createIntent,
          icon: _processing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.contactless_outlined),
          label: const Text('Envoyer au TPE'),
        ),
      ],
    );
  }

  Future<void> _createIntent() async {
    final orderId = int.tryParse(_orderController.text);
    if (orderId == null) {
      _snack('Commande invalide');
      return;
    }
    setState(() => _processing = true);
    try {
      final intent =
          await ref.read(paymentsRepositoryProvider).createTerminalIntent(
                orderId: orderId,
                readerId: _readerId,
                processOnReader: _readerId != null,
              );
      if (!mounted) {
        return;
      }
      ref.invalidate(paymentsProvider);
      ref.invalidate(paymentsSummaryProvider);
      _snack('Paiement ${intent.payment.id} cree');
    } catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MoneyTile extends StatelessWidget {
  const _MoneyTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}
