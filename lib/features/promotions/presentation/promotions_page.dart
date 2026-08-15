import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/cards/stat_card.dart';
import 'package:app_admin_staff/design_system/components/feedback/app_feedback.dart';
import 'package:app_admin_staff/design_system/components/forms/pill_filter_bar.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/promotions/data/promotions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PromotionsPage extends ConsumerWidget {
  const PromotionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promos = ref.watch(promotionsProvider);
    final statusFilter = ref.watch(promotionStatusFilterProvider);
    final search = ref.watch(promotionSearchProvider);
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    final isAdmin = user?.role == 'admin' || user?.role == 'super-admin';

    return Padding(
      padding: EdgeInsets.all(
        Breakpoints.isMobile(context) ? AppSpacing.md : AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Promotions',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Codes, periodes et conditions',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Rafraichir',
                child: IconButton.filledTonal(
                  onPressed: () => ref.invalidate(promotionsProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(width: AppSpacing.xs),
                Tooltip(
                  message: 'Generer une campagne',
                  child: IconButton.filledTonal(
                    onPressed: () => _showCampaignDialog(context, ref),
                    icon: const Icon(Icons.auto_awesome_motion_outlined),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton.icon(
                  onPressed: () => _showPromotionDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle promotion'),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          promos.when(
            data: (items) => _PromotionStats(items: items),
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.md),
          _PromotionFilters(search: search, selected: statusFilter),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: promos.when(
              data: (items) {
                final visible = _filterPromotions(items, statusFilter, search);
                if (visible.isEmpty) {
                  return const AppFeedback(
                    kind: AppFeedbackKind.noResults,
                    title: 'Aucune promotion',
                    message: 'Aucun code ne correspond aux filtres.',
                  );
                }
                if (Breakpoints.isCompactDesktop(context) ||
                    Breakpoints.isMobile(context)) {
                  return ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) => _PromotionCard(
                      promo: visible[index],
                      isAdmin: isAdmin,
                    ),
                  );
                }
                return _PromotionsTable(items: visible, isAdmin: isAdmin);
              },
              loading: () => const AppFeedback(
                kind: AppFeedbackKind.loading,
                title: 'Chargement des promotions',
              ),
              error: (error, stackTrace) => AppFeedback(
                kind: AppFeedbackKind.error,
                title: 'Promotions indisponibles',
                message: _errorMessage(error),
                onRetry: () => ref.invalidate(promotionsProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<PromotionAdminItem> _filterPromotions(
    List<PromotionAdminItem> items,
    PromotionStatusFilter status,
    String search,
  ) {
    final normalized = search.trim().toUpperCase();
    return items.where((promo) {
      if (normalized.isNotEmpty &&
          !promo.code.toUpperCase().contains(normalized) &&
          !(promo.description ?? '').toUpperCase().contains(normalized)) {
        return false;
      }
      return switch (status) {
        PromotionStatusFilter.all => true,
        PromotionStatusFilter.active =>
          _statusFor(promo) == PromotionVisualStatus.active,
        PromotionStatusFilter.inactive =>
          _statusFor(promo) == PromotionVisualStatus.inactive,
        PromotionStatusFilter.scheduled =>
          _statusFor(promo) == PromotionVisualStatus.scheduled,
        PromotionStatusFilter.expired =>
          _statusFor(promo) == PromotionVisualStatus.expired,
      };
    }).toList();
  }

  Future<void> _showPromotionDialog(
    BuildContext context,
    WidgetRef ref, {
    PromotionAdminItem? promo,
  }) async {
    final code = TextEditingController(text: promo?.code ?? '');
    final description = TextEditingController(text: promo?.description ?? '');
    final value = TextEditingController(
      text: promo?.discountValue.toString() ?? '10',
    );
    final min = TextEditingController(
      text: promo?.minOrderAmount.toString() ?? '0',
    );
    final maxUses =
        TextEditingController(text: promo?.maxUses?.toString() ?? '');
    final maxPerUser = TextEditingController(
      text: promo?.maxUsesPerUser?.toString() ?? '',
    );
    final startsAt =
        TextEditingController(text: _formatDateInput(promo?.startsAt));
    final endsAt = TextEditingController(text: _formatDateInput(promo?.endsAt));
    var discountType = promo?.discountType ?? 'percent';
    var isPublic = promo?.isPublic ?? true;
    var isStackable = promo?.isStackable ?? false;
    var firstOrderOnly = promo?.firstOrderOnly ?? false;
    var emailVerifiedRequired = promo?.emailVerifiedRequired ?? false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            promo == null ? 'Nouvelle promotion' : 'Modifier ${promo.code}',
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: code,
                    decoration: const InputDecoration(labelText: 'Code'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: discountType,
                          decoration: const InputDecoration(labelText: 'Type'),
                          items: const [
                            DropdownMenuItem(
                              value: 'percent',
                              child: Text('Pourcentage'),
                            ),
                            DropdownMenuItem(
                              value: 'fixed',
                              child: Text('Montant'),
                            ),
                          ],
                          onChanged: (newValue) {
                            setState(
                              () => discountType = newValue ?? discountType,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: value,
                          decoration:
                              const InputDecoration(labelText: 'Valeur'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: min,
                          decoration: const InputDecoration(
                            labelText: 'Minimum commande',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: maxUses,
                          decoration: const InputDecoration(
                            labelText: 'Limite globale',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: maxPerUser,
                          decoration:
                              const InputDecoration(labelText: 'Limite client'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startsAt,
                          decoration:
                              const InputDecoration(labelText: 'Debut ISO'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: endsAt,
                          decoration:
                              const InputDecoration(labelText: 'Fin ISO'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Code public'),
                    value: isPublic,
                    onChanged: (value) => setState(() => isPublic = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Premiere commande uniquement'),
                    value: firstOrderOnly,
                    onChanged: (value) =>
                        setState(() => firstOrderOnly = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cumulable'),
                    value: isStackable,
                    onChanged: (value) => setState(() => isStackable = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Email verifie requis'),
                    value: emailVerifiedRequired,
                    onChanged: (value) =>
                        setState(() => emailVerifiedRequired = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer'),
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

    final parsed = _promotionForm(
      context,
      code: code.text,
      description: description.text,
      discountType: discountType,
      value: value.text,
      min: min.text,
      maxUses: maxUses.text,
      maxPerUser: maxPerUser.text,
      startsAt: startsAt.text,
      endsAt: endsAt.text,
      isPublic: isPublic,
      isStackable: isStackable,
      firstOrderOnly: firstOrderOnly,
      emailVerifiedRequired: emailVerifiedRequired,
    );
    if (parsed == null) {
      return;
    }

    try {
      final repository = ref.read(promotionsRepositoryProvider);
      if (promo == null) {
        await repository.create(
          code: parsed.code,
          description: parsed.description,
          discountType: parsed.discountType,
          discountValue: parsed.discountValue,
          minOrderAmount: parsed.minOrderAmount,
          isPublic: parsed.isPublic,
          isStackable: parsed.isStackable,
          firstOrderOnly: parsed.firstOrderOnly,
          emailVerifiedRequired: parsed.emailVerifiedRequired,
          maxUses: parsed.maxUses,
          maxUsesPerUser: parsed.maxUsesPerUser,
          startsAt: parsed.startsAt,
          endsAt: parsed.endsAt,
        );
      } else {
        await repository.update(
          promoId: promo.id,
          code: parsed.code,
          description: parsed.description,
          discountType: parsed.discountType,
          discountValue: parsed.discountValue,
          minOrderAmount: parsed.minOrderAmount,
          isPublic: parsed.isPublic,
          isStackable: parsed.isStackable,
          firstOrderOnly: parsed.firstOrderOnly,
          emailVerifiedRequired: parsed.emailVerifiedRequired,
          maxUses: parsed.maxUses,
          maxUsesPerUser: parsed.maxUsesPerUser,
          startsAt: parsed.startsAt,
          endsAt: parsed.endsAt,
        );
      }
      ref.invalidate(promotionsProvider);
      if (!context.mounted) {
        return;
      }
      _showSnack(
        context,
        promo == null ? 'Promotion creee' : 'Promotion mise a jour',
      );
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, _errorMessage(error));
      }
    }
  }

  Future<void> _showCampaignDialog(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final prefix = TextEditingController(text: 'CAMP');
    final count = TextEditingController(text: '10');
    final description = TextEditingController();
    final value = TextEditingController(text: '10');
    final min = TextEditingController(text: '0');
    var discountType = 'percent';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Generer une campagne'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: prefix,
                  decoration: const InputDecoration(labelText: 'Prefixe'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: count,
                  decoration:
                      const InputDecoration(labelText: 'Nombre de codes'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: discountType,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'percent',
                      child: Text('Pourcentage'),
                    ),
                    DropdownMenuItem(value: 'fixed', child: Text('Montant')),
                  ],
                  onChanged: (newValue) {
                    setState(() => discountType = newValue ?? discountType);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: value,
                        decoration: const InputDecoration(labelText: 'Valeur'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: min,
                        decoration: const InputDecoration(labelText: 'Minimum'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Generer'),
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
    try {
      final campaign =
          await ref.read(promotionsRepositoryProvider).bulkGenerate(
                name: name.text,
                prefix: prefix.text,
                count: int.tryParse(count.text) ?? 10,
                description: description.text,
                discountType: discountType,
                discountValue: _double(value.text),
                minOrderAmount: _double(min.text),
              );
      ref.invalidate(promotionsProvider);
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Campagne ${campaign.name}'),
          content: SizedBox(
            width: 480,
            child: SelectableText(campaign.codes.join('\n')),
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
        _showSnack(context, _errorMessage(error));
      }
    }
  }
}

class _PromotionStats extends StatelessWidget {
  const _PromotionStats({required this.items});

  final List<PromotionAdminItem> items;

  @override
  Widget build(BuildContext context) {
    final active = items.where(
      (promo) => _statusFor(promo) == PromotionVisualStatus.active,
    );
    final usageCount = items.fold<int>(
      0,
      (sum, promo) => sum + promo.usageCount,
    );
    final revenue = items.fold<double>(
      0,
      (sum, promo) => sum + promo.revenueNet,
    );
    final discount = items.fold<double>(
      0,
      (sum, promo) => sum + promo.discountTotal,
    );
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        AppStatCard(
          label: 'Promotions actives',
          value: active.length.toString(),
          icon: Icons.local_offer_outlined,
          accentColor: AppColors.success,
          subtitle: '${items.length} codes au total',
        ),
        AppStatCard(
          label: 'Usages',
          value: usageCount.toString(),
          icon: Icons.confirmation_number_outlined,
          accentColor: AppColors.infoAlt,
          subtitle: 'Depuis les donnees API',
        ),
        AppStatCard(
          label: 'CA net attribue',
          value: formatMoney(revenue),
          icon: Icons.payments_outlined,
          accentColor: AppColors.accent,
          subtitle: 'Champ revenue_net',
        ),
        AppStatCard(
          label: 'Remises accordees',
          value: formatMoney(discount),
          icon: Icons.percent_outlined,
          accentColor: AppColors.warning,
          subtitle: 'Champ discount_total',
        ),
      ],
    );
  }
}

class _PromotionFilters extends ConsumerWidget {
  const _PromotionFilters({
    required this.search,
    required this.selected,
  });

  final String search;
  final PromotionStatusFilter selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 360,
            child: TextFormField(
              initialValue: search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Rechercher un code',
              ),
              onChanged: (value) {
                ref.read(promotionSearchProvider.notifier).state = value;
              },
            ),
          ),
          PillFilterBar<PromotionStatusFilter>(
            selected: selected,
            onSelected: (value) {
              ref.read(promotionStatusFilterProvider.notifier).state = value;
            },
            options: const [
              PillFilterOption(
                value: PromotionStatusFilter.all,
                label: 'Toutes',
                icon: Icons.all_inclusive,
              ),
              PillFilterOption(
                value: PromotionStatusFilter.active,
                label: 'Actives',
                icon: Icons.play_circle_outline,
              ),
              PillFilterOption(
                value: PromotionStatusFilter.scheduled,
                label: 'Planifiees',
                icon: Icons.schedule,
              ),
              PillFilterOption(
                value: PromotionStatusFilter.expired,
                label: 'Expirees',
                icon: Icons.event_busy_outlined,
              ),
              PillFilterOption(
                value: PromotionStatusFilter.inactive,
                label: 'Inactives',
                icon: Icons.pause_circle_outline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PromotionsTable extends ConsumerWidget {
  const _PromotionsTable({
    required this.items,
    required this.isAdmin,
  });

  final List<PromotionAdminItem> items;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowHeight: 48,
          dataRowMinHeight: 68,
          dataRowMaxHeight: 78,
          columns: const [
            DataColumn(label: Text('Code')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Periode')),
            DataColumn(label: Text('Conditions')),
            DataColumn(label: Text('Usages')),
            DataColumn(label: Text('CA net')),
            DataColumn(label: Text('Statut')),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final promo in items)
              DataRow(
                cells: [
                  DataCell(_CodeCell(promo: promo)),
                  DataCell(Text(_discountLabel(promo))),
                  DataCell(Text(_periodLabel(promo))),
                  DataCell(Text(_conditionsLabel(promo))),
                  DataCell(Text(_usageLabel(promo))),
                  DataCell(Text(formatMoney(promo.revenueNet))),
                  DataCell(_StatusForPromotion(promo: promo)),
                  DataCell(_PromotionActions(promo: promo, isAdmin: isAdmin)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PromotionCard extends ConsumerWidget {
  const _PromotionCard({
    required this.promo,
    required this.isAdmin,
  });

  final PromotionAdminItem promo;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _CodeCell(promo: promo)),
              _StatusForPromotion(promo: promo),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: [
              _Meta(label: 'Type', value: _discountLabel(promo)),
              _Meta(label: 'Periode', value: _periodLabel(promo)),
              _Meta(label: 'Conditions', value: _conditionsLabel(promo)),
              _Meta(label: 'Usages', value: _usageLabel(promo)),
              _Meta(label: 'CA net', value: formatMoney(promo.revenueNet)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: _PromotionActions(promo: promo, isAdmin: isAdmin),
          ),
        ],
      ),
    );
  }
}

class _PromotionActions extends ConsumerWidget {
  const _PromotionActions({
    required this.promo,
    required this.isAdmin,
  });

  final PromotionAdminItem promo;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isAdmin) {
      return IconButton(
        tooltip: 'Usages',
        onPressed: () => _showUsages(context, ref, promo),
        icon: const Icon(Icons.insights_outlined),
      );
    }
    return Wrap(
      spacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message: promo.isActive ? 'Desactiver' : 'Activer',
          child: Switch(
            value: promo.isActive,
            onChanged: (value) async {
              try {
                await ref.read(promotionsRepositoryProvider).toggle(
                      promo.id,
                      value,
                    );
                ref.invalidate(promotionsProvider);
                if (!context.mounted) {
                  return;
                }
                _showSnack(
                  context,
                  value ? 'Promotion activee' : 'Promotion desactivee',
                );
              } catch (error) {
                if (context.mounted) {
                  _showSnack(context, _errorMessage(error));
                }
              }
            },
          ),
        ),
        IconButton(
          tooltip: 'Usages',
          onPressed: () => _showUsages(context, ref, promo),
          icon: const Icon(Icons.insights_outlined),
        ),
        IconButton(
          tooltip: 'Modifier',
          onPressed: () => const PromotionsPage()._showPromotionDialog(
            context,
            ref,
            promo: promo,
          ),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Supprimer',
          onPressed: () => _deletePromotion(context, ref, promo),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  Future<void> _showUsages(
    BuildContext context,
    WidgetRef ref,
    PromotionAdminItem promo,
  ) async {
    try {
      final usages =
          await ref.read(promotionsRepositoryProvider).usages(promo.id);
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Usages ${promo.code}'),
          content: SizedBox(
            width: 620,
            child: usages.isEmpty
                ? const Text('Aucun usage')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final usage in usages)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Commande #${usage.orderId}'),
                          subtitle: Text(
                            'Client #${usage.userId} - ${usage.orderStatus ?? '-'}',
                          ),
                          trailing: Text(formatMoney(usage.discountTotal)),
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
        _showSnack(context, _errorMessage(error));
      }
    }
  }

  Future<void> _deletePromotion(
    BuildContext context,
    WidgetRef ref,
    PromotionAdminItem promo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer ${promo.code} ?'),
        content: const Text('Cette action utilise DELETE /promotions/{id}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    try {
      await ref.read(promotionsRepositoryProvider).delete(promo.id);
      ref.invalidate(promotionsProvider);
      if (!context.mounted) {
        return;
      }
      _showSnack(context, 'Promotion supprimee');
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, _errorMessage(error));
      }
    }
  }
}

class _CodeCell extends StatelessWidget {
  const _CodeCell({required this.promo});

  final PromotionAdminItem promo;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            promo.code,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if ((promo.description ?? '').isNotEmpty)
            Text(
              promo.description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _StatusForPromotion extends StatelessWidget {
  const _StatusForPromotion({required this.promo});

  final PromotionAdminItem promo;

  @override
  Widget build(BuildContext context) {
    final status = _statusFor(promo);
    return switch (status) {
      PromotionVisualStatus.active => const StatusBadge(
          label: 'Active',
          tone: StatusTone.success,
          icon: Icons.play_circle_outline,
          compact: true,
        ),
      PromotionVisualStatus.inactive => const StatusBadge(
          label: 'Inactive',
          tone: StatusTone.neutral,
          icon: Icons.pause_circle_outline,
          compact: true,
        ),
      PromotionVisualStatus.scheduled => const StatusBadge(
          label: 'Planifiee',
          tone: StatusTone.info,
          icon: Icons.schedule,
          compact: true,
        ),
      PromotionVisualStatus.expired => const StatusBadge(
          label: 'Expiree',
          tone: StatusTone.warning,
          icon: Icons.event_busy_outlined,
          compact: true,
        ),
    };
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xxs),
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

enum PromotionVisualStatus { active, inactive, scheduled, expired }

PromotionVisualStatus _statusFor(PromotionAdminItem promo) {
  if (!promo.isActive) {
    return PromotionVisualStatus.inactive;
  }
  final now = DateTime.now();
  if (promo.startsAt != null && promo.startsAt!.isAfter(now)) {
    return PromotionVisualStatus.scheduled;
  }
  if (promo.endsAt != null && promo.endsAt!.isBefore(now)) {
    return PromotionVisualStatus.expired;
  }
  return PromotionVisualStatus.active;
}

String _discountLabel(PromotionAdminItem promo) {
  if (promo.discountType == 'percent') {
    return '${promo.discountValue.toStringAsFixed(0)}%';
  }
  return formatMoney(promo.discountValue);
}

String _periodLabel(PromotionAdminItem promo) {
  final start =
      promo.startsAt == null ? 'Maintenant' : formatDateTime(promo.startsAt);
  final end = promo.endsAt == null ? 'Sans fin' : formatDateTime(promo.endsAt);
  return '$start -> $end';
}

String _conditionsLabel(PromotionAdminItem promo) {
  final conditions = <String>[];
  if (promo.minOrderAmount > 0) {
    conditions.add('Min ${formatMoney(promo.minOrderAmount)}');
  }
  if (promo.firstOrderOnly) {
    conditions.add('1ere commande');
  }
  if (promo.maxUsesPerUser != null) {
    conditions.add('${promo.maxUsesPerUser}/client');
  }
  if (promo.emailVerifiedRequired) {
    conditions.add('Email verifie');
  }
  if (promo.hasTargets) {
    conditions.add('Cible');
  }
  if (promo.isStackable) {
    conditions.add('Cumulable');
  }
  return conditions.isEmpty ? 'Aucune' : conditions.join(' - ');
}

String _usageLabel(PromotionAdminItem promo) {
  if (promo.maxUses != null) {
    return '${promo.currentUses}/${promo.maxUses}';
  }
  return '${promo.usageCount} usage(s)';
}

_PromotionFormData? _promotionForm(
  BuildContext context, {
  required String code,
  required String description,
  required String discountType,
  required String value,
  required String min,
  required String maxUses,
  required String maxPerUser,
  required String startsAt,
  required String endsAt,
  required bool isPublic,
  required bool isStackable,
  required bool firstOrderOnly,
  required bool emailVerifiedRequired,
}) {
  final normalizedCode = code.trim().toUpperCase();
  final discountValue = _double(value);
  final minOrder = _double(min);
  final globalLimit = _intOrNull(maxUses);
  final userLimit = _intOrNull(maxPerUser);
  final parsedStart = _parseDate(startsAt);
  final parsedEnd = _parseDate(endsAt);
  if (normalizedCode.isEmpty) {
    _showSnack(context, 'Code obligatoire');
    return null;
  }
  if (discountValue <= 0) {
    _showSnack(context, 'Valeur de remise invalide');
    return null;
  }
  if (minOrder < 0) {
    _showSnack(context, 'Minimum de commande invalide');
    return null;
  }
  if ((maxUses.trim().isNotEmpty && globalLimit == null) ||
      (maxPerUser.trim().isNotEmpty && userLimit == null)) {
    _showSnack(context, 'Limites invalides');
    return null;
  }
  if (parsedStart != null &&
      parsedEnd != null &&
      !parsedEnd.isAfter(parsedStart)) {
    _showSnack(context, 'La date de fin doit suivre le debut');
    return null;
  }
  return _PromotionFormData(
    code: normalizedCode,
    description: description.trim().isEmpty ? null : description.trim(),
    discountType: discountType,
    discountValue: discountValue,
    minOrderAmount: minOrder,
    isPublic: isPublic,
    isStackable: isStackable,
    firstOrderOnly: firstOrderOnly,
    emailVerifiedRequired: emailVerifiedRequired,
    maxUses: globalLimit,
    maxUsesPerUser: userLimit,
    startsAt: parsedStart,
    endsAt: parsedEnd,
  );
}

class _PromotionFormData {
  const _PromotionFormData({
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    required this.isPublic,
    required this.isStackable,
    required this.firstOrderOnly,
    required this.emailVerifiedRequired,
    this.description,
    this.maxUses,
    this.maxUsesPerUser,
    this.startsAt,
    this.endsAt,
  });

  final String code;
  final String? description;
  final String discountType;
  final double discountValue;
  final double minOrderAmount;
  final bool isPublic;
  final bool isStackable;
  final bool firstOrderOnly;
  final bool emailVerifiedRequired;
  final int? maxUses;
  final int? maxUsesPerUser;
  final DateTime? startsAt;
  final DateTime? endsAt;
}

String _formatDateInput(DateTime? value) {
  return value == null ? '' : value.toIso8601String();
}

DateTime? _parseDate(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}

double _double(String value) {
  return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
}

int? _intOrNull(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  final parsed = int.tryParse(text);
  if (parsed == null || parsed <= 0) {
    return null;
  }
  return parsed;
}

void _showSnack(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _errorMessage(Object error) {
  return error.toString().replaceFirst('Exception: ', '');
}
