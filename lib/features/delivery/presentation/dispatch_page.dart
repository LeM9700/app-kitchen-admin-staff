import 'dart:async';

import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/delivery/presentation/establishment_dispatch_card.dart';
import 'package:app_admin_staff/features/delivery/presentation/failures_section.dart';
import 'package:app_admin_staff/features/delivery/presentation/live_drivers_map.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Etat d'un livreur vu du comptoir, en une phrase.
String driverAvailabilityLabel(DriverSummary driver) {
  if (!driver.isActive) return 'Desactive';
  if (!driver.clockedIn) return 'Non pointe';
  if (driver.onBreak) return 'En pause';
  return 'Disponible';
}

/// Pourquoi ce livreur ne peut pas recevoir de livraison, ou `null` s'il le peut.
String? driverUnavailableReason(DriverSummary driver) {
  if (!driver.isActive) return 'Desactive';
  if (!driver.clockedIn) return 'N\'a pas pointe';
  return null;
}

String dispatchErrorMessage(Object error) {
  if (error is ApiError) return error.message;
  return 'Action impossible pour le moment. Reessayez.';
}

/// Ecran du comptoir : livreurs, commandes a attribuer, livraisons en cours.
class DispatchPage extends ConsumerStatefulWidget {
  const DispatchPage({super.key});

  @override
  ConsumerState<DispatchPage> createState() => _DispatchPageState();
}

class _DispatchPageState extends ConsumerState<DispatchPage> {
  final Set<int> _selected = {};
  Timer? _refreshTimer;
  Timer? _liveTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Positions des livreurs : plus frequent que le tableau, sans depasser la limite du serveur.
    _liveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) ref.invalidate(liveDriversProvider);
    });
    // Le comptoir doit voir le pointage et les departs sans recharger a la main.
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_busy) ref.invalidate(dispatchBoardProvider);
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (success != null) _snack(success);
    } catch (error) {
      _snack(dispatchErrorMessage(error));
    } finally {
      ref.invalidate(dispatchBoardProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign(
    List<DriverSummary> drivers,
    List<int> orderIds, {
    int? excludeDriverId,
  }) async {
    final driver = await showDriverPicker(
      context,
      drivers: drivers,
      title: orderIds.length == 1
          ? 'Attribuer la commande #${orderIds.first}'
          : 'Attribuer ${orderIds.length} commandes',
      excludeDriverId: excludeDriverId,
    );
    if (driver == null || !mounted) return;
    await _run(
      () async {
        await ref
            .read(dispatchRepositoryProvider)
            .assign(orderIds: orderIds, driverId: driver.id);
        setState(_selected.clear);
      },
      success: orderIds.length == 1
          ? 'Commande #${orderIds.first} attribuee a ${driver.label}'
          : '${orderIds.length} commandes attribuees a ${driver.label}',
    );
  }

  Future<void> _deliverWithoutCode(int orderId) async {
    final reason = await showDeliverWithoutCodeDialog(context, orderId);
    if (reason == null || !mounted) return;
    await _run(
      () => ref.read(dispatchRepositoryProvider).deliverWithoutCode(orderId, reason),
      success: 'Commande #$orderId livree (sans code, motif enregistre)',
    );
  }

  Future<void> _toggleDispatch(DeliverySettings current, bool enabled) async {
    await _run(() async {
      await ref.read(deliveryRepositoryProvider).setDriverDispatch(
            enabled: enabled,
            internalEnabled: current.internalEnabled,
            expectedVersion: current.version,
          );
      ref.invalidate(deliverySettingsProvider);
    });
  }

  Future<void> _addDriver() async {
    final establishment =
        await ref.read(currentEstablishmentProvider.future);
    if (establishment == null) {
      _snack('Aucun etablissement actif.');
      return;
    }
    if (!mounted) return;
    final created = await showDialog<CreatedDriver>(
      context: context,
      builder: (context) => _NewDriverDialog(establishmentId: establishment.id),
    );
    if (created == null || !mounted) return;
    ref.invalidate(dispatchBoardProvider);
    await showDialog<void>(
      context: context,
      builder: (context) => _TemporaryPasswordDialog(created: created),
    );
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(dispatchBoardProvider);
    final settings = ref.watch(deliverySettingsProvider).valueOrNull;
    final isAdmin = ref.watch(currentPermissionSetProvider).hasRole('admin');
    final canAssign =
        ref.watch(currentPermissionSetProvider).can(AppPermission.ordersWrite);

    return board.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dispatchErrorMessage(error), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                onPressed: () => ref.invalidate(dispatchBoardProvider),
                child: const Text('Reessayer'),
              ),
            ],
          ),
        ),
      ),
      data: (data) {
        // Une commande attribuee entre-temps disparait de la selection.
        final valid = data.unassigned.map((o) => o.orderId).toSet();
        _selected.removeWhere((id) => !valid.contains(id));
        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async => ref.refresh(dispatchBoardProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  96,
                ),
                children: [
                  Text(
                    'Dispatch livraison',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (settings != null)
                    DsCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      child: SwitchListTile(
                        key: const ValueKey('dispatch-enabled-switch'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Dispatch par livreurs'),
                        subtitle: Text(
                          settings.driverDispatchEnabled
                              ? 'Une commande ne part en livraison qu\'avec un livreur assigne.'
                              : 'Coupe : le depart en livraison reste libre, sans livreur.',
                        ),
                        value: settings.driverDispatchEnabled,
                        onChanged: isAdmin && !_busy
                            ? (enabled) => _toggleDispatch(settings, enabled)
                            : null,
                      ),
                    ),
                  if (settings != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ProofSettingsCard(settings: settings, isAdmin: isAdmin),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  EstablishmentDispatchCard(isAdmin: isAdmin),
                  const SizedBox(height: AppSpacing.md),
                  FailuresSection(
                    isAdmin: isAdmin,
                    onChanged: () => ref.invalidate(dispatchBoardProvider),
                  ),
                  const LiveDriversSection(),
                  _SectionHeader(
                    title: 'Livreurs',
                    trailing: isAdmin
                        ? TextButton.icon(
                            onPressed: _busy ? null : _addDriver,
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Ajouter'),
                          )
                        : null,
                  ),
                  if (data.drivers.isEmpty)
                    const _EmptyHint(
                      'Aucun livreur. Un administrateur peut en ajouter ici.',
                    ),
                  for (final driver in data.drivers)
                    _DriverCard(
                      driver: driver,
                      canToggle: isAdmin && !_busy,
                      onToggleActive: (active) => _run(
                        () => ref
                            .read(dispatchRepositoryProvider)
                            .setDriverActive(driver.id, active),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  _SectionHeader(title: 'A attribuer (${data.unassigned.length})'),
                  if (data.unassigned.isEmpty)
                    const _EmptyHint('Aucune livraison en attente de livreur.'),
                  for (final order in data.unassigned)
                    _UnassignedTile(
                      order: order,
                      selected: _selected.contains(order.orderId),
                      enabled: canAssign && !_busy,
                      onChanged: (value) => setState(() {
                        if (value) {
                          _selected.add(order.orderId);
                        } else {
                          _selected.remove(order.orderId);
                        }
                      }),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  _SectionHeader(title: 'En cours (${data.deliveries.length})'),
                  if (data.deliveries.isEmpty)
                    const _EmptyHint('Aucune livraison attribuee.'),
                  for (final delivery in data.deliveries)
                    _DeliveryTile(
                      delivery: delivery,
                      enabled: canAssign && !_busy,
                      onReassign: () => _assign(
                        data.drivers,
                        [delivery.order.orderId],
                        excludeDriverId: delivery.driverId,
                      ),
                      onUnassign: () => _run(
                        () => ref
                            .read(dispatchRepositoryProvider)
                            .unassign(delivery.order.orderId),
                        success: 'Livreur retire de la commande #${delivery.order.orderId}',
                      ),
                      onDeliverWithoutCode: isAdmin && !delivery.canReassign
                          ? () => _deliverWithoutCode(delivery.order.orderId)
                          : null,
                    ),
                ],
              ),
            ),
            if (_selected.isNotEmpty)
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: FilledButton.icon(
                  key: const ValueKey('dispatch-assign-selected'),
                  onPressed: _busy
                      ? null
                      : () => _assign(data.drivers, _selected.toList()..sort()),
                  icon: const Icon(Icons.two_wheeler_outlined),
                  label: Text(
                    _selected.length == 1
                        ? 'Attribuer la commande #${_selected.first}'
                        : 'Attribuer ${_selected.length} commandes',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Choix du livreur : les livreurs indisponibles sont visibles mais grises, avec la raison.
Future<DriverSummary?> showDriverPicker(
  BuildContext context, {
  required List<DriverSummary> drivers,
  required String title,
  int? excludeDriverId,
}) {
  final candidates = drivers.where((d) => d.id != excludeDriverId).toList();
  return showModalBottomSheet<DriverSummary>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (candidates.isEmpty) const Text('Aucun livreur disponible.'),
            for (final driver in candidates)
              Builder(
                builder: (context) {
                  final reason = driverUnavailableReason(driver);
                  return ListTile(
                    key: ValueKey('driver-option-${driver.id}'),
                    enabled: reason == null,
                    leading: const Icon(Icons.two_wheeler_outlined),
                    title: Text(driver.label),
                    subtitle: Text(
                      reason ??
                          '${driver.activeDeliveries} en cours - ${driver.deliveredToday} livree(s) aujourd\'hui',
                    ),
                    onTap: reason == null
                        ? () => Navigator.pop(context, driver)
                        : null,
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.driver,
    required this.canToggle,
    required this.onToggleActive,
  });

  final DriverSummary driver;
  final bool canToggle;
  final ValueChanged<bool> onToggleActive;

  @override
  Widget build(BuildContext context) {
    final ready = driver.assignable && !driver.onBreak;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: DsCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driver.label,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusBadge(
                        label: driverAvailabilityLabel(driver),
                        tone: ready ? StatusTone.success : StatusTone.neutral,
                        icon: ready
                            ? Icons.check_circle_outline
                            : Icons.pause_circle_outline,
                        compact: true,
                      ),
                      StatusBadge(
                        label: '${driver.activeDeliveries} en cours',
                        tone: StatusTone.info,
                        icon: Icons.delivery_dining_outlined,
                        compact: true,
                      ),
                      StatusBadge(
                        label: '${driver.deliveredToday} livree(s)',
                        tone: StatusTone.neutral,
                        icon: Icons.done_all_outlined,
                        compact: true,
                      ),
                    ],
                  ),
                  if (driver.vehicle != null || driver.phone != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        [driver.vehicle, driver.phone]
                            .whereType<String>()
                            .join(' - '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ),
                ],
              ),
            ),
            Switch(
              key: ValueKey('driver-active-${driver.id}'),
              value: driver.isActive,
              onChanged: canToggle ? onToggleActive : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _UnassignedTile extends StatelessWidget {
  const _UnassignedTile({
    required this.order,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final DispatchOrder order;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: DsCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Checkbox(
              key: ValueKey('select-order-${order.orderId}'),
              value: selected,
              onChanged: enabled ? (value) => onChanged(value ?? false) : null,
            ),
            Expanded(child: _OrderSummary(order: order)),
          ],
        ),
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.order});

  final DispatchOrder order;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Commande #${order.orderId}',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 8),
            Text(humanStatus(order.status)),
            const Spacer(),
            Text(
              formatMoney(order.total),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        if (order.deliveryAddress != null)
          Text(
            order.deliveryAddress!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        if (order.dueOnDelivery)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: StatusBadge(
              label: 'A encaisser a la remise',
              tone: StatusTone.warning,
              icon: Icons.payments_outlined,
              compact: true,
            ),
          ),
      ],
    );
  }
}

class _DeliveryTile extends StatelessWidget {
  const _DeliveryTile({
    required this.delivery,
    required this.enabled,
    required this.onReassign,
    required this.onUnassign,
    this.onDeliverWithoutCode,
  });

  final DispatchDelivery delivery;
  final bool enabled;
  final VoidCallback onReassign;
  final VoidCallback onUnassign;

  /// Administrateur seulement, une fois le livreur parti.
  final VoidCallback? onDeliverWithoutCode;

  static String _statusLabel(String status) => switch (status) {
        'assigned' => 'Attribuee',
        'out_for_delivery' => 'En route',
        'arrived' => 'Arrive chez le client',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: DsCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OrderSummary(order: delivery.order),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.two_wheeler_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${delivery.driverName ?? 'Livreur #${delivery.driverId}'} - ${_statusLabel(delivery.status)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (onDeliverWithoutCode != null)
                  TextButton(
                    key: ValueKey('no-code-${delivery.order.orderId}'),
                    onPressed: enabled ? onDeliverWithoutCode : null,
                    child: const Text('Livrer sans code'),
                  ),
                if (delivery.canReassign) ...[
                  TextButton(
                    key: ValueKey('reassign-${delivery.order.orderId}'),
                    onPressed: enabled ? onReassign : null,
                    child: const Text('Reattribuer'),
                  ),
                  TextButton(
                    key: ValueKey('unassign-${delivery.order.orderId}'),
                    onPressed: enabled ? onUnassign : null,
                    child: const Text('Retirer'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewDriverDialog extends ConsumerStatefulWidget {
  const _NewDriverDialog({required this.establishmentId});

  final int establishmentId;

  @override
  ConsumerState<_NewDriverDialog> createState() => _NewDriverDialogState();
}

class _NewDriverDialogState extends ConsumerState<_NewDriverDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _vehicle = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && _email.text.contains('@') && _email.text.contains('.');

  Future<void> _submit() async {
    if (!_valid || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final created = await ref.read(dispatchRepositoryProvider).createDriver(
            email: _email.text,
            fullName: _name.text,
            establishmentId: widget.establishmentId,
            phone: _phone.text,
            vehicle: _vehicle.text,
          );
      if (mounted) Navigator.of(context).pop(created);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = dispatchErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau livreur'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom complet'),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _email,
                enabled: !_submitting,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email (identifiant)'),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _phone,
                enabled: !_submitting,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telephone (optionnel)'),
              ),
              TextField(
                controller: _vehicle,
                enabled: !_submitting,
                decoration: const InputDecoration(labelText: 'Vehicule (optionnel)'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valid && !_submitting ? _submit : null,
          child: const Text('Creer le livreur'),
        ),
      ],
    );
  }
}

class _TemporaryPasswordDialog extends StatelessWidget {
  const _TemporaryPasswordDialog({required this.created});

  final CreatedDriver created;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Livreur cree'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Identifiant : ${created.driver.email ?? ''}'),
          const SizedBox(height: 8),
          const Text('Mot de passe temporaire (affiche une seule fois) :'),
          const SizedBox(height: 4),
          SelectableText(
            created.temporaryPassword,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            'Le livreur devra le changer a sa premiere connexion. Il ne verra que '
            'le pointage et ses livraisons.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: created.temporaryPassword)),
          child: const Text('Copier'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
