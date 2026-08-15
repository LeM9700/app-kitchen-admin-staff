import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/app/service_mode.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/offline/sync_worker.dart';
import 'package:app_admin_staff/core/printing/printer_registry.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/cards/stat_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_breakpoints.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/auth/data/auth_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).valueOrNull;
    final status = ref.watch(tenantStatusProvider);
    final serviceMode = ref.watch(serviceModeProvider);
    final user = session?.user;
    final isAdmin = user?.role == 'admin' || user?.role == 'super-admin';
    final permissions = PermissionSet(
      role: user?.role ?? 'staff',
      permissions: user?.permissions,
    );
    final canReadPrint = permissions.can(AppPermission.printRead);
    final sessions = ref.watch(authSessionsProvider);
    final queuedActions = ref.watch(syncQueueProvider);
    final printJobs = ref.watch(printJobsProvider);
    final printConfig = canReadPrint
        ? ref.watch(tenantPrintConfigProvider)
        : const AsyncValue<TenantPrintConfig>.data(
            TenantPrintConfig(enabled: false, config: {}),
          );
    final config = isAdmin ? ref.watch(tenantConfigProvider) : null;
    final hours = isAdmin ? ref.watch(tenantBusinessHoursProvider) : null;
    final closures = isAdmin ? ref.watch(tenantClosuresProvider) : null;
    final audit = isAdmin ? ref.watch(tenantAuditProvider) : null;

    return Material(
      color: Colors.transparent,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(tenantStatusProvider);
          ref.invalidate(tenantConfigProvider);
          ref.invalidate(tenantPrintConfigProvider);
          ref.invalidate(tenantBusinessHoursProvider);
          ref.invalidate(tenantClosuresProvider);
          ref.invalidate(tenantAuditProvider);
        },
        child: ListView(
          padding: EdgeInsets.all(
            AppBreakpoints.isMobile(context) ? AppSpacing.md : AppSpacing.xxl,
          ),
          children: [
            const _SettingsHeader(),
            const SizedBox(height: AppSpacing.lg),
            _SettingsOperationsSummary(
              status: status,
              config: config,
              isAdmin: isAdmin,
              onToggleClosure: (open) => _toggleClosure(context, ref, open),
              onEditPrep: (value) => _prepTimeDialog(context, ref, value),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Session', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(session?.user?.email ?? '-'),
              subtitle: Text(
                '${session?.tenantSlug ?? '-'} - ${session?.user?.role ?? '-'}',
              ),
              trailing: FilledButton.icon(
                onPressed: () =>
                    ref.read(sessionControllerProvider.notifier).logout(),
                icon: const Icon(Icons.logout),
                label: const Text('Deconnexion'),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _passwordDialog(context, ref),
                icon: const Icon(Icons.password_outlined),
                label: const Text('Changer mot de passe'),
              ),
            ),
            const SizedBox(height: 16),
            sessions.when(
              data: (items) => ExpansionTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                leading: const Icon(Icons.devices_outlined),
                title: Text('Sessions (${items.length})'),
                children: items.map((session) {
                  return ListTile(
                    title: Text(session.userAgent ?? 'Session #${session.id}'),
                    subtitle: Text(
                      '${session.ipAddress ?? '-'} - expire ${formatDateTime(session.expiresAt)}',
                    ),
                    trailing: session.isCurrent
                        ? const Chip(label: Text('Courante'))
                        : IconButton(
                            tooltip: 'Revoquer',
                            onPressed: () async {
                              await ref
                                  .read(authRepositoryProvider)
                                  .revokeSession(session.id);
                              ref.invalidate(authSessionsProvider);
                            },
                            icon: const Icon(Icons.logout_outlined),
                          ),
                  );
                }).toList(),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => Text(error.toString()),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Mode service'),
              subtitle: const Text('Theme sombre force pendant le rush'),
              value: serviceMode,
              onChanged: (value) {
                ref.read(serviceModeProvider.notifier).state = value;
              },
            ),
            const SizedBox(height: 24),
            Text('Restaurant', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            status.when(
              data: (value) => ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                leading: Icon(
                  value.isOpen ? Icons.storefront_outlined : Icons.lock_outline,
                ),
                title: Text(value.isOpen ? 'Ouvert' : 'Ferme'),
                subtitle: Text(
                  'Preparation ${value.estimatedPrepTimeMinutes} min - ${value.activeOrdersCount} commande(s)',
                ),
                trailing: isAdmin
                    ? FilledButton.tonal(
                        onPressed: () =>
                            _toggleClosure(context, ref, value.isOpen),
                        child: Text(value.isOpen ? 'Fermer' : 'Rouvrir'),
                      )
                    : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => Text(error.toString()),
            ),
            if (isAdmin) ...[
              const SizedBox(height: 12),
              config?.when(
                    data: (value) => Column(
                      children: [
                        ListTile(
                          shape: _shape(context),
                          leading: const Icon(Icons.timer_outlined),
                          title: const Text('Temps de preparation'),
                          subtitle: Text(
                            'Normal ${value.prepTimeNormalMinutes} min - rush ${value.prepTimePeakMinutes} min - seuil ${value.peakOrdersThreshold}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Modifier',
                            onPressed: () =>
                                _prepTimeDialog(context, ref, value),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          shape: _shape(context),
                          leading: const Icon(Icons.rule_folder_outlined),
                          title: const Text('Seuil gros ajustement stock'),
                          subtitle: Text(
                            '${value.largeStockAdjustmentThreshold.toStringAsFixed(2)} unite(s)',
                          ),
                          trailing: IconButton(
                            tooltip: 'Modifier',
                            onPressed: () =>
                                _stockThresholdDialog(context, ref, value),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ),
                      ],
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (error, stackTrace) => Text(error.toString()),
                  ) ??
                  const SizedBox.shrink(),
              const SizedBox(height: 24),
              Text(
                'Horaires semaine',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              hours?.when(
                    data: (items) => Column(
                      children: List.generate(7, (day) {
                        final daySlots = items
                            .where(
                              (slot) => slot.dayOfWeek == day && slot.isActive,
                            )
                            .toList()
                          ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
                        final label = daySlots.isEmpty
                            ? 'Ferme'
                            : daySlots
                                .map(
                                  (slot) =>
                                      '${slot.opensAt} - ${slot.closesAt}',
                                )
                                .join(', ');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            shape: _shape(context),
                            leading: const Icon(Icons.schedule_outlined),
                            title: Text(_dayName(day)),
                            subtitle: Text(label),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: 'Modifier',
                                  onPressed: () => _hoursDialog(
                                    context,
                                    ref,
                                    day,
                                    daySlots.isEmpty ? null : daySlots.first,
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Fermer ce jour',
                                  onPressed: () =>
                                      _deleteHours(context, ref, day),
                                  icon: const Icon(Icons.block_outlined),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (error, stackTrace) => Text(error.toString()),
                  ) ??
                  const SizedBox.shrink(),
              const SizedBox(height: 24),
              Text(
                'Fermetures exceptionnelles',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => _closureDialog(context, ref),
                  icon: const Icon(Icons.event_busy_outlined),
                  label: const Text('Ajouter'),
                ),
              ),
              const SizedBox(height: 8),
              closures?.when(
                    data: (items) => items.isEmpty
                        ? const ListTile(
                            leading: Icon(Icons.event_available_outlined),
                            title: Text('Aucune fermeture planifiee'),
                          )
                        : Column(
                            children: items.map((closure) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  shape: _shape(context),
                                  leading:
                                      const Icon(Icons.event_busy_outlined),
                                  title: Text(closure.closureDate),
                                  subtitle: Text(
                                    closure.customMessage ??
                                        'Message par defaut',
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Supprimer',
                                    onPressed: () => _deleteClosure(
                                      context,
                                      ref,
                                      closure.id,
                                    ),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                    loading: () => const LinearProgressIndicator(),
                    error: (error, stackTrace) => Text(error.toString()),
                  ) ??
                  const SizedBox.shrink(),
              const SizedBox(height: 24),
              audit?.when(
                    data: (items) => ExpansionTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: const Icon(Icons.history_outlined),
                      title: const Text('Audit configuration'),
                      children: items.isEmpty
                          ? const [ListTile(title: Text('Aucune entree'))]
                          : items.map((entry) {
                              return ListTile(
                                title: Text(entry.fieldName),
                                subtitle: Text(
                                  '${entry.oldValue ?? '-'} -> ${entry.newValue ?? '-'}',
                                ),
                                trailing: Text(formatDateTime(entry.changedAt)),
                              );
                            }).toList(),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (error, stackTrace) => Text(error.toString()),
                  ) ??
                  const SizedBox.shrink(),
            ],
            if (canReadPrint) ...[
              const SizedBox(height: 24),
              Text(
                'Impression partagee',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              printConfig.when(
                data: (value) => ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  leading: Icon(
                    value.enabled
                        ? Icons.print_outlined
                        : Icons.print_disabled_outlined,
                  ),
                  title: Text(
                    value.enabled ? 'Impression active' : 'Impression inactive',
                  ),
                  subtitle: Text(
                    value.config.isEmpty
                        ? 'Aucune imprimante'
                        : value.config.toString(),
                  ),
                  trailing: isAdmin
                      ? IconButton(
                          tooltip: 'Configurer',
                          onPressed: () => _printDialog(context, ref, value),
                          icon: const Icon(Icons.edit_outlined),
                        )
                      : null,
                ),
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => Text(error.toString()),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Files locales',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              leading: const Icon(Icons.sync_problem_outlined),
              title: Text('Actions offline (${queuedActions.length})'),
              trailing: queuedActions.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Synchroniser',
                      onPressed: () async {
                        await ref.read(syncWorkerProvider).flush(queuedActions);
                      },
                      icon: const Icon(Icons.cloud_sync_outlined),
                    ),
              children: queuedActions.isEmpty
                  ? const [ListTile(title: Text('Aucune action'))]
                  : queuedActions.map((action) {
                      return ListTile(
                        title: Text(action.label),
                        subtitle: Text('${action.method} ${action.endpoint}'),
                        trailing: IconButton(
                          tooltip: 'Retirer',
                          onPressed: () => ref
                              .read(syncQueueProvider.notifier)
                              .remove(action.id),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      );
                    }).toList(),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              leading: const Icon(Icons.print_outlined),
              title: Text('Impressions (${printJobs.length})'),
              children: printJobs.isEmpty
                  ? const [ListTile(title: Text('Aucun ticket'))]
                  : printJobs.map((job) {
                      return ListTile(
                        title: Text(job.title),
                        subtitle: Text(
                          job.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: 'Terminer',
                          onPressed: () => ref
                              .read(printJobsProvider.notifier)
                              .markDone(job.id),
                          icon: const Icon(Icons.check_circle_outline),
                        ),
                      );
                    }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _passwordDialog(BuildContext context, WidgetRef ref) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Changer mot de passe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              decoration:
                  const InputDecoration(labelText: 'Mot de passe actuel'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: next,
              decoration:
                  const InputDecoration(labelText: 'Nouveau mot de passe'),
              obscureText: true,
            ),
          ],
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
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: current.text,
            newPassword: next.text,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mot de passe mis a jour')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _toggleClosure(
    BuildContext context,
    WidgetRef ref,
    bool currentlyOpen,
  ) async {
    final controller =
        TextEditingController(text: 'Service momentanement ferme');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(currentlyOpen ? 'Fermer le restaurant' : 'Rouvrir'),
        content: currentlyOpen
            ? TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Message client'),
              )
            : const Text('Confirmer la reouverture du service.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(tenantRepositoryProvider).toggleClosure(
            closed: currentlyOpen,
            message: currentlyOpen ? controller.text : null,
          );
      ref.invalidate(tenantStatusProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _printDialog(
    BuildContext context,
    WidgetRef ref,
    TenantPrintConfig current,
  ) async {
    var enabled = current.enabled;
    final kitchenController = TextEditingController(
      text: current.config['kitchen_printer']?.toString() ?? '',
    );
    final counterController = TextEditingController(
      text: current.config['counter_printer']?.toString() ?? '',
    );
    final kitchenHost = TextEditingController(
      text: current.config['kitchen_host']?.toString() ?? '',
    );
    final counterHost = TextEditingController(
      text: current.config['counter_host']?.toString() ?? '',
    );
    final kitchenPort = TextEditingController(
      text: current.config['kitchen_port']?.toString() ?? '9100',
    );
    final counterPort = TextEditingController(
      text: current.config['counter_port']?.toString() ?? '9100',
    );
    var kitchenTransport =
        current.config['kitchen_transport']?.toString() ?? 'pdf';
    var counterTransport =
        current.config['counter_transport']?.toString() ?? 'pdf';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Impression partagee'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activer impression'),
                  value: enabled,
                  onChanged: (value) => setState(() => enabled = value),
                ),
                _PrinterConfigFields(
                  title: 'Cuisine',
                  icon: Icons.restaurant_outlined,
                  nameController: kitchenController,
                  hostController: kitchenHost,
                  portController: kitchenPort,
                  transport: kitchenTransport,
                  onTransportChanged: (value) {
                    setState(() => kitchenTransport = value);
                  },
                ),
                const Divider(),
                _PrinterConfigFields(
                  title: 'Comptoir',
                  icon: Icons.point_of_sale_outlined,
                  nameController: counterController,
                  hostController: counterHost,
                  portController: counterPort,
                  transport: counterTransport,
                  onTransportChanged: (value) {
                    setState(() => counterTransport = value);
                  },
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
    try {
      await ref.read(tenantRepositoryProvider).updatePrintConfig(
        enabled: enabled,
        config: {
          'kitchen_printer': kitchenController.text.trim(),
          'counter_printer': counterController.text.trim(),
          'kitchen_transport': kitchenTransport,
          'counter_transport': counterTransport,
          'kitchen_host': kitchenHost.text.trim(),
          'counter_host': counterHost.text.trim(),
          'kitchen_port': int.tryParse(kitchenPort.text.trim()) ?? 9100,
          'counter_port': int.tryParse(counterPort.text.trim()) ?? 9100,
          'manual_print': true,
        },
      );
      ref.invalidate(tenantPrintConfigProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _hoursDialog(
    BuildContext context,
    WidgetRef ref,
    int day,
    BusinessHour? current,
  ) async {
    final opens =
        TextEditingController(text: _shortTime(current?.opensAt) ?? '11:00');
    final closes =
        TextEditingController(text: _shortTime(current?.closesAt) ?? '22:30');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Horaires ${_dayName(day)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: opens,
              decoration: const InputDecoration(labelText: 'Ouverture HH:mm'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: closes,
              decoration: const InputDecoration(labelText: 'Fermeture HH:mm'),
            ),
          ],
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
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(tenantRepositoryProvider).replaceBusinessHours(
            dayOfWeek: day,
            opensAt: opens.text.trim(),
            closesAt: closes.text.trim(),
          );
      ref.invalidate(tenantBusinessHoursProvider);
      ref.invalidate(tenantStatusProvider);
      ref.invalidate(tenantAuditProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _deleteHours(
    BuildContext context,
    WidgetRef ref,
    int day,
  ) async {
    try {
      await ref.read(tenantRepositoryProvider).deleteBusinessHours(day);
      ref.invalidate(tenantBusinessHoursProvider);
      ref.invalidate(tenantStatusProvider);
      ref.invalidate(tenantAuditProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _closureDialog(BuildContext context, WidgetRef ref) async {
    final date = TextEditingController();
    final message = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fermeture exceptionnelle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: date,
              decoration: const InputDecoration(labelText: 'Date YYYY-MM-DD'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: message,
              decoration: const InputDecoration(labelText: 'Message client'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(tenantRepositoryProvider).createClosure(
            closureDate: date.text.trim(),
            message: message.text,
          );
      ref.invalidate(tenantClosuresProvider);
      ref.invalidate(tenantStatusProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _deleteClosure(
    BuildContext context,
    WidgetRef ref,
    int closureId,
  ) async {
    try {
      await ref.read(tenantRepositoryProvider).deleteClosure(closureId);
      ref.invalidate(tenantClosuresProvider);
      ref.invalidate(tenantStatusProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _prepTimeDialog(
    BuildContext context,
    WidgetRef ref,
    TenantConfig current,
  ) async {
    final normal = TextEditingController(
      text: current.prepTimeNormalMinutes.toString(),
    );
    final peak =
        TextEditingController(text: current.prepTimePeakMinutes.toString());
    final threshold = TextEditingController(
      text: current.peakOrdersThreshold.toString(),
    );
    final overhead = TextEditingController(
      text: current.overheadPerOrderMinutes.toString(),
    );
    var auto = current.autoCalcPrepTime;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Temps de preparation'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Calcul automatique'),
                  value: auto,
                  onChanged: (value) => setState(() => auto = value),
                ),
                TextField(
                  controller: normal,
                  decoration:
                      const InputDecoration(labelText: 'Normal minutes'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: peak,
                  decoration: const InputDecoration(labelText: 'Rush minutes'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: threshold,
                  decoration:
                      const InputDecoration(labelText: 'Seuil commandes rush'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: overhead,
                  decoration: const InputDecoration(
                    labelText: 'Surcharge min/commande',
                  ),
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
    try {
      await ref.read(tenantRepositoryProvider).updatePreparationSettings(
            normalMinutes:
                _int(normal.text, fallback: current.prepTimeNormalMinutes),
            peakMinutes: _int(peak.text, fallback: current.prepTimePeakMinutes),
            peakOrdersThreshold: _int(
              threshold.text,
              fallback: current.peakOrdersThreshold,
            ),
            overheadPerOrderMinutes: _int(
              overhead.text,
              fallback: current.overheadPerOrderMinutes,
            ),
            autoCalcPrepTime: auto,
          );
      ref.invalidate(tenantConfigProvider);
      ref.invalidate(tenantStatusProvider);
      ref.invalidate(tenantAuditProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _stockThresholdDialog(
    BuildContext context,
    WidgetRef ref,
    TenantConfig current,
  ) async {
    final controller = TextEditingController(
      text: current.largeStockAdjustmentThreshold.toString(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seuil gros ajustement'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Quantite'),
          keyboardType: TextInputType.number,
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
    );
    if (confirmed != true) {
      return;
    }
    final threshold =
        double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
    try {
      await ref
          .read(tenantRepositoryProvider)
          .updateLargeStockAdjustmentThreshold(threshold);
      ref.invalidate(tenantConfigProvider);
      ref.invalidate(tenantAuditProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seuil mis a jour')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  ShapeBorder _shape(BuildContext context) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
  }

  String _dayName(int day) {
    final index = day < 0
        ? 0
        : day > 6
            ? 6
            : day;
    return const [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ][index];
  }

  String? _shortTime(String? value) {
    if (value == null || value.length < 5) {
      return value;
    }
    return value.substring(0, 5);
  }

  int _int(String value, {required int fallback}) {
    return int.tryParse(value.trim()) ?? fallback;
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Parametres etablissement',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Ouverture, preparation, horaires et configuration operationnelle',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _SettingsOperationsSummary extends StatelessWidget {
  const _SettingsOperationsSummary({
    required this.status,
    required this.config,
    required this.isAdmin,
    required this.onToggleClosure,
    required this.onEditPrep,
  });

  final AsyncValue<TenantStatus> status;
  final AsyncValue<TenantConfig>? config;
  final bool isAdmin;
  final ValueChanged<bool> onToggleClosure;
  final ValueChanged<TenantConfig> onEditPrep;

  @override
  Widget build(BuildContext context) {
    return status.when(
      data: (value) {
        final cards = [
          AppStatCard(
            label: 'Etat service',
            value: value.isOpen ? 'Ouvert' : 'Ferme',
            subtitle: value.message ?? 'Statut public',
            icon: value.isOpen ? Icons.storefront_outlined : Icons.lock_outline,
            accentColor: value.isOpen ? AppColors.success : AppColors.danger,
          ),
          AppStatCard(
            label: 'Preparation',
            value: '${value.estimatedPrepTimeMinutes} min',
            subtitle: '${value.activeOrdersCount} commande(s) active(s)',
            icon: Icons.timer_outlined,
            accentColor: AppColors.infoAlt,
          ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final operations = _OperationalStateCard(
              status: value,
              isAdmin: isAdmin,
              onToggleClosure: onToggleClosure,
            );
            final prep = config?.when(
                  data: (tenantConfig) => _PreparationSettingsCard(
                    config: tenantConfig,
                    onEdit: () => onEditPrep(tenantConfig),
                  ),
                  loading: () => const DsCard(child: LinearProgressIndicator()),
                  error: (error, stackTrace) => DsCard(
                    child: Text(error.toString()),
                  ),
                ) ??
                const SizedBox.shrink();
            final content = [
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: cards,
              ),
              const SizedBox(height: AppSpacing.md),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: operations),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: prep),
                  ],
                )
              else
                Column(
                  children: [
                    operations,
                    const SizedBox(height: AppSpacing.md),
                    prep,
                  ],
                ),
            ];
            return Column(children: content);
          },
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (error, stackTrace) => EmptyState(
        icon: Icons.error_outline,
        title: 'Parametres indisponibles',
        subtitle: error.toString(),
      ),
    );
  }
}

class _OperationalStateCard extends StatelessWidget {
  const _OperationalStateCard({
    required this.status,
    required this.isAdmin,
    required this.onToggleClosure,
  });

  final TenantStatus status;
  final bool isAdmin;
  final ValueChanged<bool> onToggleClosure;

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
                  'Etat restaurant',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusBadge(
                label: status.isOpen ? 'Ouvert' : 'Ferme',
                tone: status.isOpen ? StatusTone.success : StatusTone.danger,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            status.message ?? 'Aucun message temporaire',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          if (status.nextOpening != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Prochaine ouverture: ${status.nextOpening}'),
          ],
          if (isAdmin) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => onToggleClosure(status.isOpen),
                icon: Icon(
                  status.isOpen ? Icons.lock_outline : Icons.lock_open_outlined,
                ),
                label: Text(status.isOpen ? 'Fermer' : 'Rouvrir'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreparationSettingsCard extends StatelessWidget {
  const _PreparationSettingsCard({
    required this.config,
    required this.onEdit,
  });

  final TenantConfig config;
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
                  'Preparation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Modifier',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              StatusBadge(
                label: 'Normal ${config.prepTimeNormalMinutes} min',
                tone: StatusTone.info,
                compact: true,
              ),
              StatusBadge(
                label: 'Rush ${config.prepTimePeakMinutes} min',
                tone: StatusTone.warning,
                compact: true,
              ),
              StatusBadge(
                label: config.autoCalcPrepTime ? 'Auto' : 'Manuel',
                tone: config.autoCalcPrepTime
                    ? StatusTone.success
                    : StatusTone.neutral,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Seuil rush ${config.peakOrdersThreshold} commande(s), surcharge ${config.overheadPerOrderMinutes} min/commande',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Timezone ${config.timezone}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _PrinterConfigFields extends StatelessWidget {
  const _PrinterConfigFields({
    required this.title,
    required this.icon,
    required this.nameController,
    required this.hostController,
    required this.portController,
    required this.transport,
    required this.onTransportChanged,
  });

  final String title;
  final IconData icon;
  final TextEditingController nameController;
  final TextEditingController hostController;
  final TextEditingController portController;
  final String transport;
  final ValueChanged<String> onTransportChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Nom imprimante',
            prefixIcon: Icon(icon),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: transport,
          decoration: const InputDecoration(labelText: 'Transport'),
          items: const [
            DropdownMenuItem(value: 'pdf', child: Text('PDF')),
            DropdownMenuItem(value: 'windows', child: Text('Windows')),
            DropdownMenuItem(value: 'network', child: Text('Reseau ESC/POS')),
            DropdownMenuItem(value: 'bluetooth', child: Text('Bluetooth')),
            DropdownMenuItem(value: 'usb_sunmi', child: Text('USB/Sunmi')),
          ],
          onChanged: (value) => onTransportChanged(value ?? transport),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: hostController,
                decoration:
                    const InputDecoration(labelText: 'Host / ID device'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: portController,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
