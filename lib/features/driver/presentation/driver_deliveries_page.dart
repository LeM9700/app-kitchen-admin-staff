import 'dart:async';

import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/driver/presentation/driver_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

String driverErrorMessage(Object error) {
  if (error is ApiError) return error.message;
  return 'Action impossible pour le moment. Verifiez votre connexion et reessayez.';
}

/// Lien d'itineraire : le point GPS si on l'a, sinon l'adresse.
Uri? routeUriFor(DriverDelivery delivery) {
  if (delivery.hasPoint) {
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${delivery.deliveryLat},${delivery.deliveryLng}',
      'travelmode': 'driving',
    });
  }
  final address = delivery.deliveryAddress?.trim();
  if (address == null || address.isEmpty) return null;
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': address,
    'travelmode': 'driving',
  });
}

Uri? phoneUriFor(DriverDelivery delivery) {
  final phone = delivery.customerPhone?.replaceAll(RegExp(r'[^0-9+]'), '');
  if (phone == null || phone.isEmpty) return null;
  return Uri(scheme: 'tel', path: phone);
}

/// Ecran principal du livreur : « En cours » puis « A venir ».
class DriverDeliveriesPage extends ConsumerStatefulWidget {
  const DriverDeliveriesPage({super.key});

  @override
  ConsumerState<DriverDeliveriesPage> createState() =>
      _DriverDeliveriesPageState();
}

class _DriverDeliveriesPageState extends ConsumerState<DriverDeliveriesPage> {
  final Set<int> _selected = {};
  // Appels passes au client depuis cet ecran, par livraison : l'API les exige avant de laisser
  // declarer un client absent ou injoignable.
  final Map<int, int> _calls = {};
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Le comptoir peut attribuer ou retirer une livraison a tout moment.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_busy) ref.invalidate(driverDeliveriesProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      _snack(driverErrorMessage(error));
    } finally {
      ref
        ..invalidate(driverDeliveriesProvider)
        ..invalidate(driverRecapProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Uri? uri, String failure) async {
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    _snack(failure);
  }

  Future<void> _depart() async {
    final ids = _selected.toList();
    await _run(
      () async {
        await ref.read(dispatchRepositoryProvider).depart(ids);
        setState(_selected.clear);
      },
      success: ids.length == 1 ? 'Bon depart !' : 'Bon depart avec ${ids.length} commandes !',
    );
  }

  Future<void> _call(DriverDelivery delivery) async {
    setState(() => _calls[delivery.id] = (_calls[delivery.id] ?? 0) + 1);
    await _open(phoneUriFor(delivery), 'Appel impossible');
  }

  Future<void> _deliver(DriverDelivery delivery) async {
    final input = await showDeliveryProofDialog(context, delivery);
    if (input == null) return;
    await _run(
      () => ref.read(dispatchRepositoryProvider).delivered(
            delivery.id,
            cashReceived: input.cash,
            code: input.code,
          ),
      success: 'Commande #${delivery.orderId} livree',
    );
  }

  Future<void> _fail(DriverDelivery delivery) async {
    final input = await showFailureDialog(
      context,
      delivery,
      callAttempts: _calls[delivery.id] ?? 0,
    );
    if (input == null) return;
    await _run(
      () => ref.read(dispatchRepositoryProvider).failed(
            delivery.id,
            reason: input.reason,
            note: input.note,
            callAttempts: _calls[delivery.id] ?? 0,
          ),
      success: 'Echec declare : le restaurant va statuer',
    );
  }

  @override
  Widget build(BuildContext context) {
    final deliveries = ref.watch(driverDeliveriesProvider);
    return deliveries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(driverErrorMessage(error), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                onPressed: () => ref.invalidate(driverDeliveriesProvider),
                child: const Text('Reessayer'),
              ),
            ],
          ),
        ),
      ),
      data: (items) {
        final ongoing = items.where((d) => d.isOngoing).toList();
        final upcoming = items.where((d) => !d.isOngoing).toList()
          ..sort((a, b) {
            if (a.canDepart != b.canDepart) return a.canDepart ? -1 : 1;
            return a.orderId.compareTo(b.orderId);
          });
        final departable = upcoming.where((d) => d.canDepart).map((d) => d.id).toSet();
        _selected.removeWhere((id) => !departable.contains(id));
        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async => ref.refresh(driverDeliveriesProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  96,
                ),
                children: [
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Center(
                        child: Text(
                          'Aucune livraison pour le moment.\nTirez pour actualiser.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  if (ongoing.isNotEmpty) ...[
                    _Header('En cours (${ongoing.length})'),
                    for (final delivery in ongoing)
                      _DeliveryCard(
                        delivery: delivery,
                        busy: _busy,
                        callCount: _calls[delivery.id] ?? 0,
                        onCall: () => _call(delivery),
                        onRoute: () =>
                            _open(routeUriFor(delivery), 'Itineraire indisponible'),
                        onFailed: () => _fail(delivery),
                        onArrived: delivery.phase == 'en_route'
                            ? () => _run(
                                  () => ref
                                      .read(dispatchRepositoryProvider)
                                      .arrived(delivery.id),
                                  success: 'Client prevenu de votre arrivee',
                                )
                            : null,
                        onDelivered: () => _deliver(delivery),
                      ),
                  ],
                  if (upcoming.isNotEmpty) ...[
                    _Header('A venir (${upcoming.length})'),
                    for (final delivery in upcoming)
                      _DeliveryCard(
                        delivery: delivery,
                        busy: _busy,
                        selected: _selected.contains(delivery.id),
                        onSelectedChanged: delivery.canDepart
                            ? (value) => setState(() {
                                  if (value) {
                                    _selected.add(delivery.id);
                                  } else {
                                    _selected.remove(delivery.id);
                                  }
                                })
                            : null,
                        onCall: () => _call(delivery),
                        onRoute: () =>
                            _open(routeUriFor(delivery), 'Itineraire indisponible'),
                      ),
                  ],
                ],
              ),
            ),
            if (_selected.isNotEmpty)
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: FilledButton.icon(
                  key: const ValueKey('driver-depart'),
                  onPressed: _busy ? null : _depart,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    _selected.length == 1
                        ? 'Partir avec 1 commande'
                        : 'Partir avec ${_selected.length} commandes',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({
    required this.delivery,
    required this.busy,
    required this.onCall,
    required this.onRoute,
    this.selected = false,
    this.onSelectedChanged,
    this.onArrived,
    this.onDelivered,
    this.onFailed,
    this.callCount = 0,
  });

  final DriverDelivery delivery;
  final bool busy;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;
  final VoidCallback onCall;
  final VoidCallback onRoute;
  final VoidCallback? onArrived;
  final VoidCallback? onDelivered;
  final VoidCallback? onFailed;
  final int callCount;

  (String, StatusTone) get _phaseBadge => switch (delivery.phase) {
        'arrived' => ('Arrive chez le client', StatusTone.success),
        'en_route' => ('En route', StatusTone.info),
        'ready' => ('Prete : vous pouvez partir', StatusTone.success),
        _ => ('En preparation', StatusTone.warning),
      };

  @override
  Widget build(BuildContext context) {
    final (label, tone) = _phaseBadge;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DsCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (onSelectedChanged != null)
                  Checkbox(
                    key: ValueKey('select-delivery-${delivery.id}'),
                    value: selected,
                    onChanged: busy ? null : (v) => onSelectedChanged!(v ?? false),
                  ),
                Expanded(
                  child: Text(
                    'Commande #${delivery.orderId}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                StatusBadge(label: label, tone: tone, compact: true),
              ],
            ),
            const SizedBox(height: 6),
            if (delivery.customerName != null)
              Text(
                delivery.customerName!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            Text(delivery.deliveryAddress ?? 'Adresse indisponible'),
            if (delivery.deliveryInstructions != null &&
                delivery.deliveryInstructions!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  delivery.deliveryInstructions!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusBadge(
                  label: '${delivery.itemsCount} article(s)',
                  tone: StatusTone.neutral,
                  compact: true,
                ),
                if (delivery.amountDue > 0)
                  StatusBadge(
                    label: 'Encaisser ${formatMoney(delivery.amountDue)}',
                    tone: StatusTone.warning,
                    icon: Icons.payments_outlined,
                    compact: true,
                  )
                else
                  const StatusBadge(
                    label: 'Deja payee',
                    tone: StatusTone.success,
                    icon: Icons.check_circle_outline,
                    compact: true,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('call-${delivery.id}'),
                  onPressed: delivery.customerPhone == null ? null : onCall,
                  icon: const Icon(Icons.call_outlined),
                  label: Text(callCount > 0 ? 'Appeler ($callCount)' : 'Appeler'),
                ),
                OutlinedButton.icon(
                  key: ValueKey('route-${delivery.id}'),
                  onPressed: onRoute,
                  icon: const Icon(Icons.directions_outlined),
                  label: const Text('Itineraire'),
                ),
                if (onArrived != null)
                  FilledButton.tonalIcon(
                    key: ValueKey('arrived-${delivery.id}'),
                    onPressed: busy ? null : onArrived,
                    icon: const Icon(Icons.location_on_outlined),
                    label: const Text('Arrive'),
                  ),
                if (onFailed != null)
                  OutlinedButton.icon(
                    key: ValueKey('failed-${delivery.id}'),
                    onPressed: busy ? null : onFailed,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.report_problem_outlined),
                    label: const Text('Echec'),
                  ),
                if (onDelivered != null)
                  FilledButton.icon(
                    key: ValueKey('delivered-${delivery.id}'),
                    onPressed: busy ? null : onDelivered,
                    icon: const Icon(Icons.done_all),
                    label: const Text('Livre'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
