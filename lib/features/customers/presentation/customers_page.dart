import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/cards/stat_card.dart';
import 'package:app_admin_staff/design_system/components/feedback/app_feedback.dart';
import 'package:app_admin_staff/design_system/components/forms/pill_filter_bar.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/customers/data/customers_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final _customersQueryProvider = StateProvider<CustomersQuery>((ref) {
  return const CustomersQuery();
});

final _selectedCustomerIdProvider = StateProvider<int?>((ref) => null);

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({
    this.initialCustomerId,
    super.key,
  });

  final int? initialCustomerId;

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialCustomerId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(_selectedCustomerIdProvider.notifier).state =
            widget.initialCustomerId;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(_customersQueryProvider);
    final customers = ref.watch(adminCustomersProvider(query));
    final selectedId =
        widget.initialCustomerId ?? ref.watch(_selectedCustomerIdProvider);

    return Padding(
      padding: EdgeInsets.all(
        Breakpoints.isMobile(context) ? AppSpacing.md : AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CustomersHeader(
            onExport: () => _exportCsv(context, ref, query),
            onBulkMessage: () => _sendBulkMessage(context, ref, query),
          ),
          const SizedBox(height: AppSpacing.lg),
          customers.when(
            data: (page) => _CustomerStats(items: page.items),
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.md),
          _CustomersFilters(
            controller: _searchController,
            query: query,
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: customers.when(
              data: (page) {
                if (page.items.isEmpty) {
                  return const AppFeedback(
                    kind: AppFeedbackKind.noResults,
                    title: 'Aucun client',
                    message: 'Aucun compte client ne correspond aux filtres.',
                  );
                }
                final effectiveSelected = _resolveSelection(
                  page.items,
                  selectedId,
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final current = ref.read(_selectedCustomerIdProvider);
                  if (current != effectiveSelected.id) {
                    ref.read(_selectedCustomerIdProvider.notifier).state =
                        effectiveSelected.id;
                  }
                });

                if (Breakpoints.isMobile(context) ||
                    Breakpoints.isCompactDesktop(context)) {
                  return ListView(
                    children: [
                      for (final customer in page.items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _CustomerCard(
                            customer: customer,
                            selected: customer.id == effectiveSelected.id,
                            onTap: () =>
                                _selectCustomer(context, ref, customer),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      _CustomerDetailPanel(customerId: effectiveSelected.id),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 760,
                      child: _CustomersTable(
                        customers: page.items,
                        selectedId: effectiveSelected.id,
                        onSelect: (customer) =>
                            _selectCustomer(context, ref, customer),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(
                      child: _CustomerDetailPanel(
                        customerId: effectiveSelected.id,
                      ),
                    ),
                  ],
                );
              },
              loading: () => const AppFeedback(
                kind: AppFeedbackKind.loading,
                title: 'Chargement des clients',
              ),
              error: (error, stackTrace) => AppFeedback(
                kind: AppFeedbackKind.error,
                title: 'Chargement impossible',
                message: _errorMessage(error),
                onRetry: () => ref.invalidate(adminCustomersProvider(query)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomersHeader extends StatelessWidget {
  const _CustomersHeader({
    required this.onExport,
    required this.onBulkMessage,
  });

  final VoidCallback onExport;
  final VoidCallback onBulkMessage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Clients', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Comptes, commandes et communications',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export CSV'),
            ),
            FilledButton.icon(
              onPressed: onBulkMessage,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Notifier'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CustomerStats extends StatelessWidget {
  const _CustomerStats({required this.items});

  final List<CustomerListItem> items;

  @override
  Widget build(BuildContext context) {
    final active = items.where((item) => item.isActive).length;
    final optInPush = items.where((item) => item.marketingPushOptIn).length;
    final orders = items.fold<int>(0, (total, item) => total + item.orderCount);
    final spent =
        items.fold<double>(0, (total, item) => total + item.totalSpent);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        AppStatCard(
          label: 'Clients',
          value: items.length.toString(),
          icon: Icons.people_alt_outlined,
          accentColor: AppColors.accent,
        ),
        AppStatCard(
          label: 'Actifs',
          value: active.toString(),
          icon: Icons.verified_user_outlined,
          accentColor: AppColors.success,
        ),
        AppStatCard(
          label: 'Commandes',
          value: orders.toString(),
          icon: Icons.receipt_long_outlined,
          accentColor: AppColors.infoAlt,
        ),
        AppStatCard(
          label: 'CA liste',
          value: formatMoney(spent),
          icon: Icons.euro_outlined,
          accentColor: AppColors.warning,
        ),
        AppStatCard(
          label: 'Opt-in push',
          value: optInPush.toString(),
          icon: Icons.notifications_active_outlined,
          accentColor: AppColors.info,
        ),
      ],
    );
  }
}

class _CustomersFilters extends ConsumerWidget {
  const _CustomersFilters({
    required this.controller,
    required this.query,
  });

  final TextEditingController controller;
  final CustomersQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeValue = query.isActive == null
        ? 'all'
        : query.isActive == true
            ? 'active'
            : 'inactive';
    return DsCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Rechercher',
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (value) {
                ref.read(_customersQueryProvider.notifier).state =
                    query.copyWith(
                  query: value,
                  clearQuery: value.trim().isEmpty,
                  page: 1,
                );
              },
            ),
          ),
          PillFilterBar<String>(
            options: const [
              PillFilterOption(value: 'all', label: 'Tous'),
              PillFilterOption(value: 'active', label: 'Actifs'),
              PillFilterOption(value: 'inactive', label: 'Inactifs'),
            ],
            selected: activeValue,
            onSelected: (value) {
              ref.read(_customersQueryProvider.notifier).state = query.copyWith(
                isActive: value == 'active'
                    ? true
                    : value == 'inactive'
                        ? false
                        : null,
                clearIsActive: value == 'all',
                page: 1,
              );
            },
          ),
          FilterChip(
            selected: query.emailVerified == true,
            avatar: const Icon(Icons.mark_email_read_outlined),
            label: const Text('Email verifie'),
            onSelected: (value) {
              ref.read(_customersQueryProvider.notifier).state = query.copyWith(
                emailVerified: value ? true : null,
                clearEmailVerified: !value,
                page: 1,
              );
            },
          ),
          FilterChip(
            selected: query.marketingPushOptIn == true,
            avatar: const Icon(Icons.notifications_active_outlined),
            label: const Text('Opt-in push'),
            onSelected: (value) {
              ref.read(_customersQueryProvider.notifier).state = query.copyWith(
                marketingPushOptIn: value ? true : null,
                clearMarketingPushOptIn: !value,
                page: 1,
              );
            },
          ),
          FilterChip(
            selected: query.marketingEmailOptIn == true,
            avatar: const Icon(Icons.alternate_email_outlined),
            label: const Text('Opt-in email'),
            onSelected: (value) {
              ref.read(_customersQueryProvider.notifier).state = query.copyWith(
                marketingEmailOptIn: value ? true : null,
                clearMarketingEmailOptIn: !value,
                page: 1,
              );
            },
          ),
          OutlinedButton.icon(
            onPressed: () {
              controller.clear();
              ref.read(_customersQueryProvider.notifier).state =
                  const CustomersQuery();
            },
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Reinitialiser'),
          ),
        ],
      ),
    );
  }
}

class _CustomersTable extends StatelessWidget {
  const _CustomersTable({
    required this.customers,
    required this.selectedId,
    required this.onSelect,
  });

  final List<CustomerListItem> customers;
  final int selectedId;
  final ValueChanged<CustomerListItem> onSelect;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        child: DataTable(
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('Client')),
            DataColumn(label: Text('Commandes')),
            DataColumn(label: Text('Total')),
            DataColumn(label: Text('Fidelite')),
            DataColumn(label: Text('Statut')),
          ],
          rows: [
            for (final customer in customers)
              DataRow(
                selected: customer.id == selectedId,
                onSelectChanged: (_) => onSelect(customer),
                cells: [
                  DataCell(_CustomerIdentity(customer: customer)),
                  DataCell(Text(customer.orderCount.toString())),
                  DataCell(Text(formatMoney(customer.totalSpent))),
                  DataCell(Text('${customer.loyaltyPoints} pts')),
                  DataCell(_CustomerStatus(customer: customer)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.selected,
    required this.onTap,
  });

  final CustomerListItem customer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      backgroundColor:
          selected ? AppColors.infoBg : Theme.of(context).colorScheme.surface,
      borderColor: selected ? AppColors.infoAlt : null,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ListTile(
        leading: CircleAvatar(child: Text(_initials(customer.displayName))),
        title: Text(customer.displayName),
        subtitle: Text(customer.email),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatMoney(customer.totalSpent)),
            Text('${customer.orderCount} commandes'),
          ],
        ),
      ),
    );
  }
}

class _CustomerIdentity extends StatelessWidget {
  const _CustomerIdentity({required this.customer});

  final CustomerListItem customer;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(child: Text(_initials(customer.displayName))),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(customer.displayName, overflow: TextOverflow.ellipsis),
              Text(
                customer.email,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomerStatus extends StatelessWidget {
  const _CustomerStatus({required this.customer});

  final CustomerListItem customer;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        StatusBadge(
          label: customer.isActive ? 'Actif' : 'Inactif',
          tone: customer.isActive ? StatusTone.success : StatusTone.danger,
          compact: true,
        ),
        if (customer.marketingPushOptIn)
          const StatusBadge(
            label: 'Push',
            tone: StatusTone.info,
            icon: Icons.notifications_outlined,
            compact: true,
          ),
        if (customer.marketingEmailOptIn)
          const StatusBadge(
            label: 'Email',
            tone: StatusTone.info,
            icon: Icons.alternate_email_outlined,
            compact: true,
          ),
      ],
    );
  }
}

class _CustomerDetailPanel extends ConsumerWidget {
  const _CustomerDetailPanel({required this.customerId});

  final int customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(customerDetailProvider(customerId));
    final communications =
        ref.watch(customerCommunicationsProvider(customerId));
    return detail.when(
      data: (customer) => SingleChildScrollView(
        child: Column(
          children: [
            _CustomerProfileCard(customer: customer),
            const SizedBox(height: AppSpacing.md),
            _OrdersCard(customer: customer),
            const SizedBox(height: AppSpacing.md),
            communications.when(
              data: (page) => _CommunicationsCard(
                customer: customer,
                communications: page.items,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => AppFeedback(
                kind: AppFeedbackKind.error,
                title: 'Historique indisponible',
                message: _errorMessage(error),
                onRetry: () => ref.invalidate(
                  customerCommunicationsProvider(customerId),
                ),
              ),
            ),
          ],
        ),
      ),
      loading: () => const AppFeedback(
        kind: AppFeedbackKind.loading,
        title: 'Chargement de la fiche',
      ),
      error: (error, stackTrace) => AppFeedback(
        kind: AppFeedbackKind.error,
        title: 'Fiche indisponible',
        message: _errorMessage(error),
        onRetry: () => ref.invalidate(customerDetailProvider(customerId)),
      ),
    );
  }
}

class _CustomerProfileCard extends ConsumerWidget {
  const _CustomerProfileCard({required this.customer});

  final CustomerDetail customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                child: Text(_initials(customer.displayName)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(customer.email),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _sendCustomerMessage(context, ref, customer),
                icon: const Icon(Icons.send_outlined),
                label: const Text('Envoyer'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _CustomerStatus(customer: customer),
              StatusBadge(
                label: customer.emailVerified ? 'Email verifie' : 'Non verifie',
                tone: customer.emailVerified
                    ? StatusTone.success
                    : StatusTone.warning,
                icon: Icons.mark_email_read_outlined,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoGrid(
            items: [
              _InfoItem('Telephone', customer.phone ?? '-'),
              _InfoItem('Commandes', customer.orderCount.toString()),
              _InfoItem('Total depense', formatMoney(customer.totalSpent)),
              _InfoItem('Points fidelite', '${customer.loyaltyPoints} pts'),
              _InfoItem(
                'Derniere commande',
                formatDateTime(customer.lastOrderAt),
              ),
              _InfoItem('Compte cree', formatDateTime(customer.createdAt)),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrdersCard extends ConsumerWidget {
  const _OrdersCard({required this.customer});

  final CustomerDetail customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Commandes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (customer.orders.isEmpty)
            const AppFeedback(
              kind: AppFeedbackKind.empty,
              title: 'Aucune commande',
            )
          else
            Column(
              children: [
                for (final order in customer.orders)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _OrderTile(
                      order: order,
                      onTap: () =>
                          _showOrderDetail(context, ref, customer, order),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.order,
    required this.onTap,
  });

  final OrderSummary order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        color: AppColors.adminSurfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text('#${order.id} - ${humanOrderType(order.orderType)}'),
        subtitle: Text(formatDateTime(order.createdAt)),
        trailing: Wrap(
          spacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge(
              label: humanStatus(order.status),
              tone: _toneForStatus(order.status),
              compact: true,
            ),
            Text(formatMoney(order.total)),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _CommunicationsCard extends ConsumerWidget {
  const _CommunicationsCard({
    required this.customer,
    required this.communications,
  });

  final CustomerDetail customer;
  final List<CustomerCommunication> communications;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Historique communications',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _sendCustomerMessage(context, ref, customer),
                icon: const Icon(Icons.add_alert_outlined),
                label: const Text('Nouveau'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (communications.isEmpty)
            const AppFeedback(
              kind: AppFeedbackKind.empty,
              title: 'Aucun message',
              message: 'Les emails et notifications envoyes apparaitront ici.',
            )
          else
            Column(
              children: [
                for (final item in communications)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _CommunicationTile(item: item),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CommunicationTile extends StatelessWidget {
  const _CommunicationTile({required this.item});

  final CustomerCommunication item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.adminSurfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(
                label: item.channel,
                tone: item.channel == 'email'
                    ? StatusTone.info
                    : StatusTone.success,
                icon: item.channel == 'email'
                    ? Icons.alternate_email_outlined
                    : Icons.notifications_outlined,
                compact: true,
              ),
              const SizedBox(width: AppSpacing.xs),
              StatusBadge(
                label: item.status,
                tone: _toneForCommunication(item.status),
                compact: true,
              ),
              const Spacer(),
              Text(
                formatDateTime(item.sentAt ?? item.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (item.subject != null && item.subject!.isNotEmpty)
            Text(item.subject!, style: Theme.of(context).textTheme.labelLarge),
          Text(item.body),
          if (item.error != null && item.error!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.items});

  final List<_InfoItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 520 ? 2 : 1;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final item in items)
              SizedBox(
                width: (constraints.maxWidth - AppSpacing.sm * (columns - 1)) /
                    columns,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.adminSurfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        item.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InfoItem {
  const _InfoItem(this.label, this.value);

  final String label;
  final String value;
}

Future<void> _sendCustomerMessage(
  BuildContext context,
  WidgetRef ref,
  CustomerDetail customer,
) async {
  final draft = await _messageDialog(context, ref, title: customer.displayName);
  if (draft == null) {
    return;
  }
  try {
    final result = await ref
        .read(customersRepositoryProvider)
        .sendCustomerMessage(customerId: customer.id, draft: draft);
    ref
      ..invalidate(customerCommunicationsProvider(customer.id))
      ..invalidate(customerDetailProvider(customer.id));
    if (context.mounted) {
      _snack(
        context,
        '${result.created} message(s) cree(s), ${result.skipped} ignore(s)',
      );
    }
  } catch (error) {
    if (context.mounted) {
      _snack(context, _errorMessage(error));
    }
  }
}

Future<void> _sendBulkMessage(
  BuildContext context,
  WidgetRef ref,
  CustomersQuery query,
) async {
  final draft = await _messageDialog(context, ref, title: 'clients filtres');
  if (draft == null) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  final confirmed = await _confirm(
    context,
    title: 'Envoi groupe',
    content:
        'Le message sera envoye aux clients actifs correspondant aux filtres actuels.',
  );
  if (!confirmed) {
    return;
  }
  final bulkDraft = CustomerBulkMessageDraft(
    channels: draft.channels,
    messageType: draft.messageType,
    templateKey: draft.templateKey,
    subject: draft.subject,
    body: draft.body,
    query: query.query,
    isActive: query.isActive ?? true,
    emailVerified: query.emailVerified,
    marketingEmailOptIn: query.marketingEmailOptIn,
    marketingPushOptIn: query.marketingPushOptIn,
    confirmBulkSend: true,
  );
  try {
    final result =
        await ref.read(customersRepositoryProvider).sendBulkMessage(bulkDraft);
    ref.invalidate(adminCustomersProvider);
    if (context.mounted) {
      _snack(
        context,
        '${result.created} message(s) cree(s), ${result.skipped} ignore(s)',
      );
    }
  } catch (error) {
    if (context.mounted) {
      _snack(context, _errorMessage(error));
    }
  }
}

Future<CustomerMessageDraft?> _messageDialog(
  BuildContext context,
  WidgetRef ref, {
  required String title,
}) async {
  List<CustomerMessageTemplate> templates;
  try {
    templates = await ref.read(customerMessageTemplatesProvider.future);
  } catch (_) {
    templates = const [];
  }
  if (!context.mounted) {
    return null;
  }

  final formKey = GlobalKey<FormState>();
  final subjectController = TextEditingController();
  final bodyController = TextEditingController();
  var channelEmail = false;
  var channelPush = true;
  var messageType = 'transactional';
  String? templateKey;

  final result = await showDialog<CustomerMessageDraft>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final selectedTemplate = templates
              .where((template) => template.key == templateKey)
              .firstOrNull;
          return AlertDialog(
            title: Text('Notifier $title'),
            content: SizedBox(
              width: 560,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'transactional',
                            icon: Icon(Icons.receipt_long_outlined),
                            label: Text('Transactionnel'),
                          ),
                          ButtonSegment(
                            value: 'marketing',
                            icon: Icon(Icons.local_offer_outlined),
                            label: Text('Marketing'),
                          ),
                        ],
                        selected: {messageType},
                        onSelectionChanged: (value) {
                          setState(() => messageType = value.first);
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          FilterChip(
                            selected: channelPush,
                            avatar: const Icon(Icons.notifications_outlined),
                            label: const Text('Push'),
                            onSelected: (value) {
                              setState(() => channelPush = value);
                            },
                          ),
                          FilterChip(
                            selected: channelEmail,
                            avatar: const Icon(Icons.alternate_email_outlined),
                            label: const Text('Email'),
                            onSelected: (value) {
                              setState(() => channelEmail = value);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DropdownButtonFormField<String?>(
                        initialValue: templateKey,
                        decoration: const InputDecoration(
                          labelText: 'Modele',
                          prefixIcon: Icon(Icons.article_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Message personnalise'),
                          ),
                          for (final template in templates)
                            DropdownMenuItem<String?>(
                              value: template.key,
                              child: Text(template.label),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            templateKey = value;
                            final template = templates
                                .where((item) => item.key == value)
                                .firstOrNull;
                            if (template != null) {
                              messageType = template.messageType;
                              channelEmail =
                                  template.channels.contains('email');
                              channelPush = template.channels.contains('push');
                              subjectController.text = template.subject ?? '';
                              bodyController.text = template.body;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: subjectController,
                        decoration: const InputDecoration(
                          labelText: 'Sujet email',
                          prefixIcon: Icon(Icons.subject_outlined),
                        ),
                        validator: (value) {
                          if (channelEmail &&
                              selectedTemplate == null &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Sujet requis pour un email personnalise';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: bodyController,
                        minLines: 4,
                        maxLines: 7,
                        decoration: const InputDecoration(
                          labelText: 'Message',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
                        validator: (value) {
                          if (selectedTemplate == null &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Message requis';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (!channelEmail && !channelPush) {
                    _snack(context, 'Choisis au moins un canal');
                    return;
                  }
                  if (formKey.currentState?.validate() != true) {
                    return;
                  }
                  Navigator.pop(
                    context,
                    CustomerMessageDraft(
                      channels: [
                        if (channelPush) 'push',
                        if (channelEmail) 'email',
                      ],
                      messageType: messageType,
                      templateKey: templateKey,
                      subject: subjectController.text,
                      body: bodyController.text,
                    ),
                  );
                },
                icon: const Icon(Icons.send_outlined),
                label: const Text('Envoyer'),
              ),
            ],
          );
        },
      );
    },
  );

  subjectController.dispose();
  bodyController.dispose();
  return result;
}

Future<void> _showOrderDetail(
  BuildContext context,
  WidgetRef ref,
  CustomerDetail customer,
  OrderSummary order,
) async {
  try {
    final detail = await ref
        .read(customersRepositoryProvider)
        .customerOrderDetail(customerId: customer.id, orderId: order.id);
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Commande #${detail.order.id}'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: _OrderDetailContent(detail: detail),
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
      _snack(context, _errorMessage(error));
    }
  }
}

class _OrderDetailContent extends StatelessWidget {
  const _OrderDetailContent({required this.detail});

  final CustomerOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _DetailPill('Type', humanOrderType(order.orderType)),
            _DetailPill('Statut', humanStatus(order.status)),
            _DetailPill('Paiement', order.paymentStatus),
            _DetailPill('Total', formatMoney(order.total)),
            if (order.deliveryAddress != null)
              _DetailPill('Adresse', order.deliveryAddress!),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Produits', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        for (final item in order.items)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${item.quantity} x ${item.productName ?? 'Produit'}'),
            subtitle: Text(
              [
                if (item.variantName != null) item.variantName,
                if (item.extras.isNotEmpty)
                  item.extras.map((extra) => extra.name).join(', '),
              ].whereType<String>().join(' - '),
            ),
            trailing: Text(formatMoney(item.total)),
          ),
        if (detail.payment != null) ...[
          const Divider(height: 28),
          Text(
            'Stripe / paiement',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          _PaymentSummaryBlock(payment: detail.payment!),
        ],
      ],
    );
  }
}

class _PaymentSummaryBlock extends StatelessWidget {
  const _PaymentSummaryBlock({required this.payment});

  final PaymentDetail payment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _DetailPill('Encaisse', formatCents(payment.paidAmountCents)),
        _DetailPill('Rembourse', formatCents(payment.refundedAmountCents)),
        _DetailPill(
          'Remboursable',
          formatCents(payment.remainingRefundableCents),
        ),
        _DetailPill('Provider', payment.payment.provider),
        _DetailPill('Statut', payment.payment.status),
        if (payment.refunds.isNotEmpty)
          _DetailPill(
            'Annulations / remboursements',
            '${payment.refunds.length}',
          ),
      ],
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.adminSurfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}

Future<void> _exportCsv(
  BuildContext context,
  WidgetRef ref,
  CustomersQuery query,
) async {
  try {
    final csv = await ref.read(customersRepositoryProvider).exportCsv(query);
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export clients CSV'),
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
    if (context.mounted) {
      _snack(context, _errorMessage(error));
    }
  }
}

CustomerListItem _resolveSelection(
  List<CustomerListItem> customers,
  int? selectedId,
) {
  for (final customer in customers) {
    if (customer.id == selectedId) {
      return customer;
    }
  }
  return customers.first;
}

void _selectCustomer(
  BuildContext context,
  WidgetRef ref,
  CustomerListItem customer,
) {
  ref.read(_selectedCustomerIdProvider.notifier).state = customer.id;
  if (Breakpoints.isMobile(context)) {
    context.go('/customers/${customer.id}');
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String content,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ) ??
      false;
}

StatusTone _toneForStatus(String status) {
  return switch (status) {
    'delivered' || 'confirmed' || 'ready' => StatusTone.success,
    'cancelled' || 'failed' => StatusTone.danger,
    'pending' || 'pending_confirmation' => StatusTone.warning,
    _ => StatusTone.info,
  };
}

StatusTone _toneForCommunication(String status) {
  return switch (status) {
    'sent' => StatusTone.success,
    'failed' => StatusTone.danger,
    'skipped' => StatusTone.warning,
    _ => StatusTone.info,
  };
}

String _initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length == 1) {
    return parts.first.characters.first.toUpperCase();
  }
  return '${parts.first.characters.first}${parts.last.characters.first}'
      .toUpperCase();
}

String _errorMessage(Object error) {
  if (error is AppException) {
    if (error.statusCode == 403) {
      return 'Acces refuse';
    }
    if (error.statusCode == 422) {
      return error.field == null
          ? error.message
          : '${error.field}: ${error.message}';
    }
    return error.message;
  }
  return error.toString();
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
