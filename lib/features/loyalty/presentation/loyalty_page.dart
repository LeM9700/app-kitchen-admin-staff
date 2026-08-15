import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/cards/stat_card.dart';
import 'package:app_admin_staff/design_system/components/feedback/app_feedback.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/loyalty/data/loyalty_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoyaltyPage extends ConsumerStatefulWidget {
  const LoyaltyPage({super.key});

  @override
  ConsumerState<LoyaltyPage> createState() => _LoyaltyPageState();
}

class _LoyaltyPageState extends ConsumerState<LoyaltyPage> {
  final _customerController = TextEditingController();
  LoyaltyAccount? _account;
  List<LoyaltyTransaction> _transactions = const [];
  String? _lookupError;
  bool _lookupLoading = false;

  @override
  void dispose() {
    _customerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    final isAdmin = user?.role == 'admin' || user?.role == 'super-admin';
    final config = isAdmin ? ref.watch(loyaltyConfigProvider) : null;
    final stats = isAdmin ? ref.watch(loyaltyStatsProvider) : null;
    final rules = isAdmin ? ref.watch(loyaltyRulesProvider) : null;
    final rewards = isAdmin ? ref.watch(loyaltyRewardsProvider) : null;

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
                      'Programme de fidelite',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Configuration, regles et soldes clients',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Rafraichir',
                child: IconButton.filledTonal(
                  onPressed: isAdmin
                      ? () {
                          ref.invalidate(loyaltyConfigProvider);
                          ref.invalidate(loyaltyStatsProvider);
                          ref.invalidate(loyaltyRulesProvider);
                          ref.invalidate(loyaltyRewardsProvider);
                        }
                      : null,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(width: AppSpacing.xs),
                Tooltip(
                  message: 'Nouvelle regle',
                  child: IconButton.filledTonal(
                    onPressed: () => _ruleDialog(context, ref),
                    icon: const Icon(Icons.rule_outlined),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton.icon(
                  onPressed: () => _rewardDialog(context, ref),
                  icon: const Icon(Icons.card_giftcard_outlined),
                  label: const Text('Recompense'),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!isAdmin)
            Expanded(
              child: ListView(
                children: [
                  const AppFeedback(
                    kind: AppFeedbackKind.forbidden,
                    title: 'Configuration reservee aux admins',
                    message:
                        'La consultation client reste accessible aux roles staff.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _customerLookup(context, ref),
                ],
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(loyaltyConfigProvider);
                  ref.invalidate(loyaltyStatsProvider);
                  ref.invalidate(loyaltyRulesProvider);
                  ref.invalidate(loyaltyRewardsProvider);
                },
                child: ListView(
                  children: [
                    stats?.when(
                          data: (value) => _LoyaltyStats(stats: value),
                          loading: () => const LinearProgressIndicator(),
                          error: (error, stackTrace) => AppFeedback(
                            kind: AppFeedbackKind.error,
                            title: 'Statistiques indisponibles',
                            message: _errorMessage(error),
                            onRetry: () => ref.invalidate(loyaltyStatsProvider),
                          ),
                        ) ??
                        const SizedBox.shrink(),
                    const SizedBox(height: AppSpacing.md),
                    if (Breakpoints.isCompactDesktop(context) ||
                        Breakpoints.isMobile(context))
                      Column(
                        children: [
                          config?.when(
                                data: (value) => _ConfigPanel(
                                  config: value,
                                  onEdit: () =>
                                      _configDialog(context, ref, value),
                                ),
                                loading: () => const LinearProgressIndicator(),
                                error: (error, stackTrace) => AppFeedback(
                                  kind: AppFeedbackKind.error,
                                  title: 'Configuration indisponible',
                                  message: _errorMessage(error),
                                  onRetry: () =>
                                      ref.invalidate(loyaltyConfigProvider),
                                ),
                              ) ??
                              const SizedBox.shrink(),
                          const SizedBox(height: AppSpacing.md),
                          _RulesPanel(rules: rules),
                          const SizedBox(height: AppSpacing.md),
                          _RewardsPanel(rewards: rewards),
                          const SizedBox(height: AppSpacing.md),
                          _customerLookup(context, ref),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              children: [
                                config?.when(
                                      data: (value) => _ConfigPanel(
                                        config: value,
                                        onEdit: () =>
                                            _configDialog(context, ref, value),
                                      ),
                                      loading: () =>
                                          const LinearProgressIndicator(),
                                      error: (error, stackTrace) => AppFeedback(
                                        kind: AppFeedbackKind.error,
                                        title: 'Configuration indisponible',
                                        message: _errorMessage(error),
                                        onRetry: () => ref
                                            .invalidate(loyaltyConfigProvider),
                                      ),
                                    ) ??
                                    const SizedBox.shrink(),
                                const SizedBox(height: AppSpacing.md),
                                _RulesPanel(rules: rules),
                                const SizedBox(height: AppSpacing.md),
                                _RewardsPanel(rewards: rewards),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xl),
                          Expanded(
                            flex: 2,
                            child: _customerLookup(context, ref),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _customerLookup(BuildContext context, WidgetRef ref) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Client et points',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.person_search_outlined),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _customerController,
                  decoration: const InputDecoration(
                    labelText: 'User ID',
                    prefixIcon: Icon(Icons.person_search_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _lookup(ref),
                ),
              ),
              FilledButton.icon(
                onPressed: _lookupLoading ? null : () => _lookup(ref),
                icon: _lookupLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: const Text('Consulter'),
              ),
            ],
          ),
          if (_lookupError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _lookupError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_account != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _MiniMetric(
                  label: 'Points',
                  value: _account!.points.toString(),
                ),
                _MiniMetric(
                  label: 'Valeur',
                  value: formatMoney(_account!.pointValueEuros),
                ),
                _MiniMetric(
                  label: 'Expire bientot',
                  value: _account!.expiringSoonPoints.toString(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Historique recent',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_transactions.isEmpty)
              Text(
                'Aucun mouvement',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              for (final transaction in _transactions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${transaction.pointsDelta > 0 ? '+' : ''}${transaction.pointsDelta} pts',
                  ),
                  subtitle:
                      Text('${transaction.reason} - ${transaction.source}'),
                  trailing: Text(formatDateTime(transaction.createdAt)),
                ),
          ],
        ],
      ),
    );
  }

  Future<void> _lookup(WidgetRef ref) async {
    final userId = int.tryParse(_customerController.text.trim());
    if (userId == null) {
      setState(() => _lookupError = 'User ID invalide');
      return;
    }
    setState(() {
      _lookupLoading = true;
      _lookupError = null;
    });
    try {
      final repository = ref.read(loyaltyRepositoryProvider);
      final account = await repository.account(userId);
      final transactions = await repository.transactions(userId);
      if (!mounted) {
        return;
      }
      setState(() {
        _account = account;
        _transactions = transactions;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _lookupError = _errorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _lookupLoading = false);
      }
    }
  }

  Future<void> _configDialog(
    BuildContext context,
    WidgetRef ref,
    LoyaltyConfig config,
  ) async {
    final base = TextEditingController(text: config.baseRatio.toString());
    final rate =
        TextEditingController(text: config.pointsToEuroRate.toString());
    final cap =
        TextEditingController(text: config.maxCumulativeMultiplier.toString());
    final expiry =
        TextEditingController(text: config.pointsExpiryDays?.toString() ?? '');
    var active = config.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Configuration fidelite'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Programme actif'),
                  value: active,
                  onChanged: (value) => setState(() => active = value),
                ),
                TextField(
                  controller: base,
                  decoration:
                      const InputDecoration(labelText: 'Points par euro'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: rate,
                  decoration:
                      const InputDecoration(labelText: 'Valeur du point EUR'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: cap,
                  decoration: const InputDecoration(
                    labelText: 'Plafond multiplicateur',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: expiry,
                  decoration:
                      const InputDecoration(labelText: 'Expiration jours'),
                  keyboardType: TextInputType.number,
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
    try {
      await ref.read(loyaltyRepositoryProvider).updateConfig(
            baseRatio: _double(base.text, fallback: config.baseRatio),
            pointsExpiryDays: int.tryParse(expiry.text),
            pointsToEuroRate:
                _double(rate.text, fallback: config.pointsToEuroRate),
            maxCumulativeMultiplier: _double(
              cap.text,
              fallback: config.maxCumulativeMultiplier,
            ),
            isActive: active,
          );
      ref.invalidate(loyaltyConfigProvider);
      ref.invalidate(loyaltyStatsProvider);
      if (!context.mounted) {
        return;
      }
      _showSnack(context, 'Configuration mise a jour');
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, _errorMessage(error));
      }
    }
  }

  Future<void> _ruleDialog(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final multiplier = TextEditingController(text: '2');
    var type = 'first_order';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nouvelle regle'),
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
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'first_order',
                      child: Text('Premiere commande'),
                    ),
                    DropdownMenuItem(
                      value: 'day_multiplier',
                      child: Text('Jour bonus'),
                    ),
                  ],
                  onChanged: (value) => setState(() => type = value ?? type),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: multiplier,
                  decoration:
                      const InputDecoration(labelText: 'Multiplicateur'),
                  keyboardType: TextInputType.number,
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
              child: const Text('Creer'),
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
    if (name.text.trim().isEmpty) {
      _showSnack(context, 'Nom obligatoire');
      return;
    }
    try {
      await ref.read(loyaltyRepositoryProvider).createRule(
            name: name.text.trim(),
            ruleType: type,
            multiplier: _double(multiplier.text, fallback: 2),
          );
      ref.invalidate(loyaltyRulesProvider);
      if (!context.mounted) {
        return;
      }
      _showSnack(context, 'Regle creee');
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, _errorMessage(error));
      }
    }
  }

  Future<void> _rewardDialog(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final points = TextEditingController(text: '100');
    final amount = TextEditingController(text: '5');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle recompense'),
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
                controller: points,
                decoration: const InputDecoration(labelText: 'Points'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: amount,
                decoration: const InputDecoration(labelText: 'Reduction EUR'),
                keyboardType: TextInputType.number,
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
            child: const Text('Creer'),
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
    if (name.text.trim().isEmpty) {
      _showSnack(context, 'Nom obligatoire');
      return;
    }
    try {
      await ref.read(loyaltyRepositoryProvider).createReward(
            name: name.text.trim(),
            rewardType: 'discount_euros',
            pointsRequired: int.tryParse(points.text) ?? 100,
            discountAmount: _double(amount.text, fallback: 5),
          );
      ref.invalidate(loyaltyRewardsProvider);
      if (!context.mounted) {
        return;
      }
      _showSnack(context, 'Recompense creee');
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, _errorMessage(error));
      }
    }
  }
}

class _LoyaltyStats extends StatelessWidget {
  const _LoyaltyStats({required this.stats});

  final LoyaltyStats stats;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        AppStatCard(
          label: 'Membres',
          value: stats.memberCount.toString(),
          icon: Icons.group_outlined,
          accentColor: AppColors.infoAlt,
          subtitle: '${stats.activeMemberCount} actifs',
        ),
        AppStatCard(
          label: 'Points emis',
          value: stats.pointsDistributed.toString(),
          icon: Icons.add_circle_outline,
          accentColor: AppColors.success,
          subtitle: '${stats.circulatingBalance} en circulation',
        ),
        AppStatCard(
          label: 'Points utilises',
          value: stats.pointsRedeemed.toString(),
          icon: Icons.redeem_outlined,
          accentColor: AppColors.accent,
          subtitle: '${stats.redemptionRate.toStringAsFixed(1)}% redemption',
        ),
        AppStatCard(
          label: 'Points expires',
          value: stats.pointsExpired.toString(),
          icon: Icons.timer_off_outlined,
          accentColor: AppColors.warning,
        ),
      ],
    );
  }
}

class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel({
    required this.config,
    required this.onEdit,
  });

  final LoyaltyConfig config;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Configuration du programme',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _activeBadge(config.isActive),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                tooltip: 'Configurer',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _MiniMetric(
                label: 'Base',
                value: '${config.baseRatio} point/euro',
              ),
              _MiniMetric(
                label: 'Valeur point',
                value: formatMoney(config.pointsToEuroRate),
              ),
              _MiniMetric(
                label: 'Expiration',
                value: config.pointsExpiryDays == null
                    ? 'Desactivee'
                    : '${config.pointsExpiryDays} jours',
              ),
              _MiniMetric(
                label: 'Plafond bonus',
                value: 'x${config.maxCumulativeMultiplier}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RulesPanel extends ConsumerWidget {
  const _RulesPanel({required this.rules});

  final AsyncValue<List<LoyaltyRule>>? rules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Regles bonus', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          rules?.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const AppFeedback(
                      kind: AppFeedbackKind.empty,
                      title: 'Aucune regle',
                    );
                  }
                  return Column(
                    children: [
                      for (final rule in items)
                        _RuleRow(
                          rule: rule,
                          onToggle: (value) async {
                            try {
                              await ref
                                  .read(loyaltyRepositoryProvider)
                                  .updateRule(
                                    ruleId: rule.id,
                                    isActive: value,
                                  );
                              ref.invalidate(loyaltyRulesProvider);
                            } catch (error) {
                              if (context.mounted) {
                                _showSnack(context, _errorMessage(error));
                              }
                            }
                          },
                        ),
                    ],
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => AppFeedback(
                  kind: AppFeedbackKind.error,
                  title: 'Regles indisponibles',
                  message: _errorMessage(error),
                  onRetry: () => ref.invalidate(loyaltyRulesProvider),
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _RewardsPanel extends ConsumerWidget {
  const _RewardsPanel({required this.rewards});

  final AsyncValue<List<LoyaltyReward>>? rewards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recompenses', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          rewards?.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const AppFeedback(
                      kind: AppFeedbackKind.empty,
                      title: 'Aucune recompense',
                    );
                  }
                  return Column(
                    children: [
                      for (final reward in items)
                        _RewardRow(
                          reward: reward,
                          onToggle: (value) async {
                            try {
                              await ref
                                  .read(loyaltyRepositoryProvider)
                                  .updateReward(
                                    rewardId: reward.id,
                                    isActive: value,
                                  );
                              ref.invalidate(loyaltyRewardsProvider);
                            } catch (error) {
                              if (context.mounted) {
                                _showSnack(context, _errorMessage(error));
                              }
                            }
                          },
                        ),
                    ],
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => AppFeedback(
                  kind: AppFeedbackKind.error,
                  title: 'Recompenses indisponibles',
                  message: _errorMessage(error),
                  onRetry: () => ref.invalidate(loyaltyRewardsProvider),
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.onToggle,
  });

  final LoyaltyRule rule;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.rule_outlined),
      title: Text(rule.name),
      subtitle: Text(
        '${_ruleTypeLabel(rule.ruleType)} - x${rule.multiplier} - priorite ${rule.priority}',
      ),
      trailing: Wrap(
        spacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _activeBadge(rule.isActive),
          Switch(value: rule.isActive, onChanged: onToggle),
        ],
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.reward,
    required this.onToggle,
  });

  final LoyaltyReward reward;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.card_giftcard_outlined),
      title: Text(reward.name),
      subtitle: Text(_rewardLabel(reward)),
      trailing: Wrap(
        spacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _activeBadge(reward.isActive),
          Switch(value: reward.isActive, onChanged: onToggle),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, minHeight: 64),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

StatusBadge _activeBadge(bool active) {
  return StatusBadge(
    label: active ? 'Actif' : 'Inactif',
    tone: active ? StatusTone.success : StatusTone.neutral,
    icon: active ? Icons.play_circle_outline : Icons.pause_circle_outline,
    compact: true,
  );
}

String _ruleTypeLabel(String value) {
  return switch (value) {
    'category_multiplier' => 'Categorie',
    'period_multiplier' => 'Periode',
    'day_multiplier' => 'Jour',
    'first_order' => 'Premiere commande',
    _ => value,
  };
}

String _rewardLabel(LoyaltyReward reward) {
  if (reward.rewardType == 'discount_euros') {
    return '${reward.pointsRequired} points - ${formatMoney(reward.discountAmount ?? 0)}';
  }
  if (reward.productId != null) {
    return '${reward.pointsRequired} points - produit #${reward.productId}';
  }
  return '${reward.pointsRequired} points - ${reward.rewardType}';
}

double _double(String value, {double fallback = 0}) {
  return double.tryParse(value.trim().replaceAll(',', '.')) ?? fallback;
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
