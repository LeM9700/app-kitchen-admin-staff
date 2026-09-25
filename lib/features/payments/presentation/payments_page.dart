import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/config/stripe_connect_callbacks.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/forms/pill_filter_bar.dart';
import 'package:app_admin_staff/design_system/tokens/app_breakpoints.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_elevation.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
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
    final horizontalPadding =
        AppBreakpoints.isMobile(context) ? AppSpacing.md : AppSpacing.xxl;

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        padding: EdgeInsets.all(horizontalPadding),
        children: [
          _PaymentsHeader(
            canExport: canRefund,
            onExport: () => _exportCsv(context, ref),
            onRefresh: () => _refresh(ref),
          ),
          const SizedBox(height: AppSpacing.lg),
          summary.when(
            data: (value) => _PaymentsSummary(summary: value),
            loading: () => const _PaymentsSummarySkeleton(),
            error: (error, stackTrace) => _LoadErrorCard(
              title: 'Impossible de charger la synthese',
              message: _friendlyError(error),
              onRetry: () => ref.invalidate(paymentsSummaryProvider),
            ),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1120;
              final transactions = payments.when(
                data: (items) => _PaymentsLedger(
                  payments: _filterPayments(items, _search),
                  canRefund: canRefund,
                  onDetail: (payment) => _detail(context, ref, payment),
                  onRefund: (payment) => _refund(context, ref, payment),
                ),
                loading: () => const _PaymentsLedgerSkeleton(),
                error: (error, stackTrace) => _LoadErrorCard(
                  title: 'Impossible de charger les paiements',
                  message: _friendlyError(error),
                  onRetry: () => ref.invalidate(paymentsProvider),
                ),
              );
              final infrastructure = _PaymentsInfrastructure(
                canRefund: canRefund,
                canUseTerminal: canUseTerminal,
                connect: connect,
                readers: readers,
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: transactions),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 3, child: infrastructure),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  transactions,
                  if (canRefund || canUseTerminal) ...[
                    const SizedBox(height: AppSpacing.lg),
                    infrastructure,
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(paymentsSummaryProvider);
    ref.invalidate(paymentsProvider);
    ref.invalidate(terminalReadersProvider);
    ref.invalidate(connectStatusProvider);
    await Future.wait([
      ref.read(paymentsSummaryProvider.future),
      ref.read(paymentsProvider.future),
    ]);
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
    late final PaymentDetail detail;
    try {
      detail =
          await ref.read(paymentsRepositoryProvider).detail(payment.orderId);
    } catch (error) {
      if (context.mounted) {
        _snack(context, 'Impossible de charger le paiement');
      }
      return;
    }
    if (!context.mounted) {
      return;
    }

    final draft = await showModalBottomSheet<_RefundDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _RefundSheet(detail: detail),
    );
    if (draft == null || !context.mounted) {
      return;
    }

    try {
      await ref.read(paymentsRepositoryProvider).refund(
            orderId: payment.orderId,
            amountCents: draft.amountCents,
            reason: draft.reason,
          );
      ref.invalidate(paymentsSummaryProvider);
      ref.invalidate(paymentsProvider);
      if (context.mounted) {
        _snack(context, 'Remboursement envoye');
      }
    } catch (error) {
      if (context.mounted) {
        _snack(context, _friendlyError(error));
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
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => _PaymentDetailSheet(
          detail: detail,
          canRefund:
              {'paid', 'partially_refunded'}.contains(detail.payment.status) &&
                  detail.remainingRefundableCents > 0,
          onRefund: () {
            Navigator.pop(context);
            _refund(context, ref, payment);
          },
        ),
      );
    } catch (error) {
      if (context.mounted) {
        _snack(context, 'Impossible de charger le detail du paiement');
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
          title: const Text('Exporter les paiements'),
          content: SizedBox(
            width: 720,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Le format CSV est fourni par le backend financier.',
                ),
                const SizedBox(height: AppSpacing.md),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.adminSurfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.adminBorder),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: SelectableText(csv),
                  ),
                ),
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
        _snack(context, 'Impossible d exporter les paiements');
      }
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
    final mobile = AppBreakpoints.isMobile(context);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: mobile ? double.infinity : 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paiements',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Suivi des encaissements et remboursements',
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
              FilledButton.tonalIcon(
                onPressed: onExport,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Exporter'),
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

class _PaymentsSummary extends StatelessWidget {
  const _PaymentsSummary({required this.summary});

  final PaymentSummary summary;

  @override
  Widget build(BuildContext context) {
    final statusText = summary.countsByStatus.entries
        .take(3)
        .map((entry) => '${humanStatus(entry.key)} ${entry.value}')
        .join('  ');
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final cards = [
          _PaymentMetricCard(
            label: 'Collecte',
            value: formatCents(summary.collectedAmountCents),
            subtitle: '${summary.paymentCount} paiement(s)',
            icon: Icons.payments_outlined,
            tone: StatusTone.success,
          ),
          _PaymentMetricCard(
            label: 'Rembourse',
            value: formatCents(summary.refundedAmountCents),
            subtitle: '${summary.refundCount} remboursement(s)',
            icon: Icons.undo_outlined,
            tone: StatusTone.warning,
          ),
          _PaymentMetricCard(
            label: 'Net',
            value: formatCents(summary.netAmountCents),
            subtitle: 'Encaisse moins rembourse',
            icon: Icons.account_balance_wallet_outlined,
            tone: StatusTone.info,
          ),
          _PaymentMetricCard(
            label: 'Statuts',
            value: summary.countsByStatus.values
                .fold<int>(0, (a, b) => a + b)
                .toString(),
            subtitle: statusText.isEmpty ? 'Aucun statut' : statusText,
            icon: Icons.query_stats_outlined,
            tone: StatusTone.neutral,
          ),
        ];
        if (compact) {
          return Column(
            children: [
              for (final card in cards) ...[
                card,
                if (card != cards.last) const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (final card in cards) ...[
              Expanded(child: card),
              if (card != cards.last) const SizedBox(width: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

class _PaymentMetricCard extends StatelessWidget {
  const _PaymentMetricCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = StatusBadgeColors.fromTone(tone);
    return DsCard(
      height: 148,
      backgroundColor: AppColors.adminSurface,
      borderColor: AppColors.adminBorder,
      intensity: NeumorphicIntensity.subtle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 128),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, size: 18, color: colors.foreground),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
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
      intensity: NeumorphicIntensity.subtle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 760;
          final search = SizedBox(
            width: narrow ? double.infinity : 360,
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Commande, provider ou reference...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: onSearchChanged,
            ),
          );
          final filters = PillFilterBar<String?>(
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
                label: 'Rembourses',
                icon: Icons.undo_outlined,
              ),
              PillFilterOption<String?>(
                value: 'partially_refunded',
                label: 'Partiels',
                icon: Icons.tune_outlined,
              ),
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                search,
                const SizedBox(height: AppSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: filters,
                ),
              ],
            );
          }
          return Row(
            children: [
              search,
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: filters,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PaymentsLedger extends StatelessWidget {
  const _PaymentsLedger({
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
          title: 'Aucun paiement sur cette periode',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final table = constraints.maxWidth >= 860;
        return DsCard(
          padding: EdgeInsets.zero,
          borderColor: AppColors.adminBorder,
          intensity: NeumorphicIntensity.subtle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _LedgerTitle(),
              const Divider(height: 1),
              if (table)
                _PaymentsTable(
                  payments: payments,
                  canRefund: canRefund,
                  onDetail: onDetail,
                  onRefund: onRefund,
                )
              else
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    children: [
                      for (final payment in payments) ...[
                        _PaymentCard(
                          payment: payment,
                          canRefund: canRefund,
                          onDetail: onDetail,
                          onRefund: onRefund,
                        ),
                        if (payment != payments.last)
                          const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LedgerTitle extends StatelessWidget {
  const _LedgerTitle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Transactions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
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
    return Column(
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
          if (payment != payments.last) const Divider(height: 1),
        ],
      ],
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
      color: AppColors.adminSurfaceMuted.withValues(alpha: 0.55),
      child: const Row(
        children: [
          _PaymentTableLabel('Commande', width: 96),
          _PaymentTableLabel('Date', width: 118),
          _PaymentTableLabel('Provider', flex: 2),
          _PaymentTableLabel('Montant', width: 118),
          _PaymentTableLabel('Rembourse', width: 118),
          _PaymentTableLabel('Statut', width: 158),
          _PaymentTableLabel('Reference', flex: 2),
          _PaymentTableLabel('Actions', width: 104, alignRight: true),
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
    final refundable = _canRefundPayment(canRefund, payment);
    return InkWell(
      onTap: () => onDetail(payment),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(width: 96, child: Text('#${payment.orderId}')),
            SizedBox(
              width: 118,
              child: Text(formatDateTime(payment.createdAt)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _providerLabel(payment.provider),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 118,
              child: Text(
                formatMoney(payment.amount),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            SizedBox(
              width: 118,
              child: Text(formatCents(payment.refundedAmountCents)),
            ),
            SizedBox(
              width: 158,
              child: _PaymentStatusBadge(status: payment.status),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _reference(payment),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),
            SizedBox(
              width: 104,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                children: [
                  IconButton(
                    tooltip: 'Detail',
                    onPressed: () => onDetail(payment),
                    icon: const Icon(Icons.open_in_new),
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
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
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
    final refundable = _canRefundPayment(canRefund, payment);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.adminSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.adminBorder),
        boxShadow: AppElevation.raisedSm(
          AppColors.adminSurface,
          intensity: 0.45,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Commande #${payment.orderId}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      formatMoney(payment.amount),
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                  ],
                ),
              ),
              _PaymentStatusBadge(status: payment.status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${_providerLabel(payment.provider)} / ${payment.currency.toUpperCase()}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${formatDateTime(payment.createdAt)}  -  Rembourse ${formatCents(payment.refundedAmountCents)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () => onDetail(payment),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Ouvrir'),
              ),
              const Spacer(),
              if (refundable)
                IconButton.filledTonal(
                  tooltip: 'Rembourser',
                  onPressed: () => onRefund(payment),
                  icon: const Icon(Icons.undo_outlined),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentTableLabel extends StatelessWidget {
  const _PaymentTableLabel(
    this.label, {
    this.width,
    this.flex,
    this.alignRight = false,
  });

  final String label;
  final double? width;
  final int? flex;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w900,
          ),
    );
    if (width != null) {
      return SizedBox(width: width, child: text);
    }
    return Expanded(flex: flex ?? 1, child: text);
  }
}

class _PaymentsInfrastructure extends StatelessWidget {
  const _PaymentsInfrastructure({
    required this.canRefund,
    required this.canUseTerminal,
    required this.connect,
    required this.readers,
  });

  final bool canRefund;
  final bool canUseTerminal;
  final AsyncValue<ConnectStatus>? connect;
  final AsyncValue<List<TerminalReader>> readers;

  @override
  Widget build(BuildContext context) {
    if (!canRefund && !canUseTerminal) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canRefund) ...[
          connect?.when(
                data: (value) => _ConnectPanel(status: value),
                loading: () => const _InfrastructureSkeleton(
                  title: 'Compte Stripe',
                ),
                error: (error, stackTrace) => _LoadErrorCard(
                  title: 'Impossible de charger le compte Stripe',
                  message: _friendlyError(error),
                ),
              ) ??
              const SizedBox.shrink(),
          if (canUseTerminal) const SizedBox(height: AppSpacing.md),
        ],
        if (canUseTerminal)
          readers.when(
            data: (items) => _TerminalPanel(readers: items),
            loading: () => const _InfrastructureSkeleton(
              title: 'Terminal de paiement',
            ),
            error: (error, stackTrace) => _LoadErrorCard(
              title: 'Impossible de recuperer les lecteurs TPE',
              message: _friendlyError(error),
            ),
          ),
      ],
    );
  }
}

class _ConnectPanel extends ConsumerWidget {
  const _ConnectPanel({required this.status});

  final ConnectStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operational = status.onboardingComplete &&
        status.chargesEnabled &&
        status.payoutsEnabled;
    final title =
        operational ? 'Compte Stripe operationnel' : 'Onboarding requis';
    final tone = operational ? StatusTone.success : StatusTone.warning;
    return DsCard(
      intensity: NeumorphicIntensity.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color:
                      operational ? AppColors.successBg : AppColors.warningBg,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(
                  operational
                      ? Icons.verified_outlined
                      : Icons.pending_actions_outlined,
                  color: operational ? AppColors.success : AppColors.warning,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Compte Stripe',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                label: operational ? 'Actif' : 'A configurer',
                tone: tone,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _ConnectChecks(status: status),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _openOnboarding(context, ref),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Continuer la configuration'),
              ),
              OutlinedButton.icon(
                onPressed: status.detailsSubmitted
                    ? () => _openDashboard(context, ref)
                    : null,
                icon: const Icon(Icons.dashboard_outlined),
                label: const Text('Ouvrir le dashboard Stripe'),
              ),
            ],
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
    await _openUrl(context, response.url, title: 'Lien Stripe Connect');
    ref.invalidate(connectStatusProvider);
  }

  Future<void> _openDashboard(BuildContext context, WidgetRef ref) async {
    final url =
        await ref.read(paymentsRepositoryProvider).connectDashboardUrl();
    if (!context.mounted) {
      return;
    }
    await _openUrl(context, url, title: 'Dashboard Stripe');
  }
}

class _ConnectChecks extends StatelessWidget {
  const _ConnectChecks({required this.status});

  final ConnectStatus status;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CheckLine(
          label: 'Paiements autorises',
          enabled: status.chargesEnabled,
        ),
        _CheckLine(
          label: 'Virements autorises',
          enabled: status.payoutsEnabled,
        ),
        _CheckLine(
          label: 'Informations transmises',
          enabled: status.detailsSubmitted,
        ),
        if (status.stripeAccountId != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              children: [
                const Icon(Icons.tag_outlined, size: 16),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    status.stripeAccountId!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle_outline : Icons.pending_outlined,
            size: 18,
            color: enabled ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label)),
        ],
      ),
    );
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
  String? _orderError;

  @override
  void dispose() {
    _orderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedReaderId =
        _readerId ?? (widget.readers.isEmpty ? null : widget.readers.first.id);
    return DsCard(
      intensity: NeumorphicIntensity.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.infoBg,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: const Icon(
                  Icons.contactless_outlined,
                  color: AppColors.infoAlt,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Terminal de paiement',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (widget.readers.isEmpty)
            const EmptyState(
              icon: Icons.credit_card_off_outlined,
              title: 'Aucun lecteur TPE disponible',
            )
          else ...[
            for (final reader in widget.readers)
              _TerminalReaderTile(reader: reader),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _orderController,
              decoration: InputDecoration(
                labelText: 'Commande',
                hintText: '#184',
                prefixIcon: const Icon(Icons.receipt_outlined),
                errorText: _orderError,
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) {
                if (_orderError != null) {
                  setState(() => _orderError = null);
                }
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: selectedReaderId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Lecteur',
                prefixIcon: Icon(Icons.credit_card),
              ),
              items: widget.readers
                  .map(
                    (reader) => DropdownMenuItem(
                      value: reader.id,
                      child: Text(reader.label),
                    ),
                  )
                  .toList(),
              onChanged: _processing
                  ? null
                  : (value) => setState(() => _readerId = value),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _processing ? null : _createIntent,
                icon: _processing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_to_mobile_outlined),
                label: Text(_processing ? 'Envoi au TPE...' : 'Envoyer au TPE'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createIntent() async {
    final orderId = int.tryParse(_orderController.text.trim());
    if (orderId == null || orderId <= 0) {
      setState(() => _orderError = 'Commande invalide');
      return;
    }
    final readerId =
        _readerId ?? (widget.readers.isEmpty ? null : widget.readers.first.id);
    setState(() => _processing = true);
    try {
      await ref.read(paymentsRepositoryProvider).createTerminalIntent(
            orderId: orderId,
            readerId: readerId,
            processOnReader: readerId != null,
          );
      if (!mounted) {
        return;
      }
      ref.invalidate(paymentsProvider);
      ref.invalidate(paymentsSummaryProvider);
      _snack('Paiement envoye au TPE - Commande #$orderId');
    } catch (error) {
      if (mounted) {
        _snack(_friendlyError(error));
      }
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

class _TerminalReaderTile extends StatelessWidget {
  const _TerminalReaderTile({required this.reader});

  final TerminalReader reader;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reader.label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  reader.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          StatusBadge(
            label: _terminalStatusLabel(reader.status),
            tone: _terminalTone(reader.status),
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _PaymentDetailSheet extends StatelessWidget {
  const _PaymentDetailSheet({
    required this.detail,
    required this.canRefund,
    required this.onRefund,
  });

  final PaymentDetail detail;
  final bool canRefund;
  final VoidCallback onRefund;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: AppBreakpoints.isMobile(context) ? 0.94 : 0.86,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: ListView(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paiement #${detail.orderId}',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _PaymentStatusBadge(status: detail.payment.status),
                    ],
                  ),
                ),
                Text(
                  formatCents(detail.paidAmountCents),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                _MoneyTile(
                  label: 'Montant paye',
                  value: formatCents(detail.paidAmountCents),
                ),
                _MoneyTile(
                  label: 'Rembourse',
                  value: formatCents(detail.refundedAmountCents),
                ),
                _MoneyTile(
                  label: 'Encore remboursable',
                  value: formatCents(detail.remainingRefundableCents),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _DetailSection(
              title: 'Provider',
              children: [
                _DetailLine(
                  label: 'Moyen',
                  value: _providerLabel(detail.payment.provider),
                ),
                _DetailLine(
                  label: 'Statut',
                  value: humanStatus(detail.payment.status),
                ),
                _DetailLine(
                  label: 'Reference',
                  value: _reference(detail.payment),
                ),
                if (detail.receiptUrl != null && detail.receiptUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: OutlinedButton.icon(
                      onPressed: () => _openUrl(
                        context,
                        detail.receiptUrl!,
                        title: 'Recu de paiement',
                      ),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Ouvrir le recu'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _DetailSection(
              title: 'Historique remboursements',
              children: [
                if (detail.refunds.isEmpty)
                  const EmptyState(
                    icon: Icons.undo_outlined,
                    title: 'Aucun remboursement',
                  )
                else
                  for (final refund in detail.refunds)
                    _RefundHistoryTile(refund: refund),
              ],
            ),
            if (canRefund) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onRefund,
                icon: const Icon(Icons.undo_outlined),
                label: const Text('Rembourser'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RefundSheet extends StatefulWidget {
  const _RefundSheet({required this.detail});

  final PaymentDetail detail;

  @override
  State<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<_RefundSheet> {
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  _RefundMode _mode = _RefundMode.total;
  String? _amountError;
  String? _reasonError;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final canRefund = detail.remainingRefundableCents > 0;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            'Remboursement #${detail.orderId}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Vous allez creer une operation financiere serveur.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              _MoneyTile(
                label: 'Paye',
                value: formatCents(detail.paidAmountCents),
              ),
              _MoneyTile(
                label: 'Deja rembourse',
                value: formatCents(detail.refundedAmountCents),
              ),
              _MoneyTile(
                label: 'Remboursable',
                value: formatCents(detail.remainingRefundableCents),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SegmentedButton<_RefundMode>(
            segments: const [
              ButtonSegment(
                value: _RefundMode.total,
                icon: Icon(Icons.undo_outlined),
                label: Text('Total'),
              ),
              ButtonSegment(
                value: _RefundMode.partial,
                icon: Icon(Icons.tune_outlined),
                label: Text('Partiel'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: canRefund
                ? (value) {
                    setState(() {
                      _mode = value.first;
                      _amountError = null;
                    });
                  }
                : null,
          ),
          if (_mode == _RefundMode.partial) ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Montant',
                prefixIcon: const Icon(Icons.euro_outlined),
                errorText: _amountError,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) {
                if (_amountError != null) {
                  setState(() => _amountError = null);
                }
              },
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _reasonController,
            decoration: InputDecoration(
              labelText: 'Raison',
              prefixIcon: const Icon(Icons.notes_outlined),
              errorText: _reasonError,
            ),
            maxLines: 2,
            onChanged: (_) {
              if (_reasonError != null) {
                setState(() => _reasonError = null);
              }
            },
          ),
          if (!canRefund) ...[
            const SizedBox(height: AppSpacing.md),
            const StatusBadge(
              label: 'Aucun montant remboursable',
              tone: StatusTone.neutral,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: canRefund ? _submit : null,
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Rembourser'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final reason = _reasonController.text.trim();
    final remaining = widget.detail.remainingRefundableCents;
    int? amountCents;

    if (reason.isEmpty) {
      setState(() => _reasonError = 'Raison obligatoire');
      return;
    }

    if (_mode == _RefundMode.partial) {
      final amount =
          double.tryParse(_amountController.text.trim().replaceAll(',', '.'));
      amountCents = amount == null ? null : (amount * 100).round();
      if (amountCents == null || amountCents <= 0) {
        setState(() => _amountError = 'Montant invalide');
        return;
      }
      if (amountCents > remaining) {
        setState(() => _amountError = 'Montant superieur au remboursable');
        return;
      }
    }

    Navigator.pop(
      context,
      _RefundDraft(
        amountCents: amountCents,
        reason: reason,
      ),
    );
  }
}

class _RefundDraft {
  const _RefundDraft({required this.amountCents, required this.reason});

  final int? amountCents;
  final String reason;
}

enum _RefundMode { total, partial }

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      intensity: NeumorphicIntensity.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 2,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefundHistoryTile extends StatelessWidget {
  const _RefundHistoryTile({required this.refund});

  final Refund refund;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.adminSurfaceMuted.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.adminBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '-${formatCents(refund.amount)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(refund.reason ?? 'Sans raison renseignee'),
                if (refund.failureReason != null &&
                    refund.failureReason!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Echec provider: ${refund.failureReason}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _PaymentStatusBadge(status: refund.status),
              const SizedBox(height: AppSpacing.xs),
              Text(
                formatDateTime(refund.createdAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
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
    return Container(
      width: 190,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.adminSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.adminBorder),
        boxShadow:
            AppElevation.raisedSm(AppColors.adminSurface, intensity: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentStatusBadge extends StatelessWidget {
  const _PaymentStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: humanStatus(status),
      tone: _paymentTone(status),
      compact: true,
    );
  }
}

class _PaymentsSummarySkeleton extends StatelessWidget {
  const _PaymentsSummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final cards =
            List.generate(4, (_) => const _SkeletonBlock(height: 128));
        if (compact) {
          return Column(
            children: [
              for (final card in cards) ...[
                card,
                if (card != cards.last) const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (final card in cards) ...[
              Expanded(child: card),
              if (card != cards.last) const SizedBox(width: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

class _PaymentsLedgerSkeleton extends StatelessWidget {
  const _PaymentsLedgerSkeleton();

  @override
  Widget build(BuildContext context) {
    return DsCard(
      intensity: NeumorphicIntensity.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkeletonLine(width: 180, height: 20),
          const SizedBox(height: AppSpacing.lg),
          for (var index = 0; index < 6; index++) ...[
            const _SkeletonLine(width: double.infinity, height: 44),
            if (index != 5) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _InfrastructureSkeleton extends StatelessWidget {
  const _InfrastructureSkeleton({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      intensity: NeumorphicIntensity.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          const _SkeletonLine(width: double.infinity, height: 18),
          const SizedBox(height: AppSpacing.sm),
          const _SkeletonLine(width: 180, height: 18),
          const SizedBox(height: AppSpacing.md),
          const _SkeletonLine(width: double.infinity, height: 42),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      height: height,
      intensity: NeumorphicIntensity.subtle,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonLine(width: 120, height: 16),
          Spacer(),
          _SkeletonLine(width: 180, height: 28),
          SizedBox(height: AppSpacing.sm),
          _SkeletonLine(width: 150, height: 14),
        ],
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.adminSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
  }
}

class _LoadErrorCard extends StatelessWidget {
  const _LoadErrorCard({
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      borderColor: AppColors.danger.withValues(alpha: 0.28),
      intensity: NeumorphicIntensity.subtle,
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reessayer'),
            ),
          ],
        ],
      ),
    );
  }
}

bool _canRefundPayment(bool canRefund, PaymentListItem payment) {
  return canRefund && {'paid', 'partially_refunded'}.contains(payment.status);
}

StatusTone _paymentTone(String status) {
  return switch (status) {
    'paid' => StatusTone.success,
    'partially_refunded' => StatusTone.warning,
    'refunded' => StatusTone.neutral,
    'failed' || 'canceled' || 'cancelled' => StatusTone.danger,
    'pending' => StatusTone.info,
    _ => StatusTone.info,
  };
}

String _providerLabel(String provider) {
  return switch (provider) {
    'stripe_terminal' => 'Stripe Terminal',
    'stripe' => 'Stripe',
    'cash' => 'Cash',
    'card' || 'cb' => 'CB',
    _ => provider.isEmpty ? '-' : provider,
  };
}

String _reference(PaymentListItem payment) {
  return payment.externalReference ??
      payment.providerPaymentId ??
      payment.id.toString();
}

String _terminalStatusLabel(String status) {
  return switch (status) {
    'online' => 'En ligne',
    'offline' => 'Hors ligne',
    _ => humanStatus(status),
  };
}

StatusTone _terminalTone(String status) {
  return switch (status) {
    'online' => StatusTone.success,
    'offline' => StatusTone.neutral,
    _ => StatusTone.info,
  };
}

String _friendlyError(Object error) {
  if (error is AppException) {
    return error.message;
  }
  return 'Action impossible pour le moment';
}

Future<void> _openUrl(
  BuildContext context,
  String value, {
  required String title,
}) async {
  final uri = Uri.tryParse(value);
  if (uri != null && await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }
  if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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
