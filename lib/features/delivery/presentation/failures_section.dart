import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/payments/presentation/guarantee_settlement_dialog.dart'
    show parseSettlementAmount;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _apiMessage(Object error) => error is ApiError
    ? error.message
    : 'Action impossible pour le moment. Reessayez.';

// --------------------------------------------------------------------------- aides pures

/// Message d'erreur de saisie du traitement d'un echec, ou `null` si l'action peut partir.
///
/// Memes regles que l'API (`delivery/failures.py`) : aucun frais retenu en cas de faute du
/// restaurant, montant retenu positif et au plus egal au total, motif obligatoire pour retenir,
/// pas de relivraison d'une commande qui n'est plus reglee.
String? validateResolution(
  DeliveryFailure failure, {
  required String? action,
  required String amountText,
  required String note,
}) {
  switch (action) {
    case null:
      return 'Choisissez une action.';
    case 'refund':
      return null;
    case 'retain':
      if (!failure.customerFault) {
        return 'Faute du restaurant : aucun frais ne peut etre retenu.';
      }
      final amount = parseSettlementAmount(amountText);
      if (amount == null) return 'Montant a retenir requis.';
      if (amount > failure.total) {
        return 'Le montant depasse le total (${formatMoney(failure.total)}).';
      }
      if (note.trim().isEmpty)
        return 'Un motif est requis pour retenir des frais.';
      return null;
    case 'redeliver':
      return failure.canRedeliver
          ? null
          : 'Cette commande n\'est plus reglee : elle ne peut pas etre relivree.';
  }
  return 'Action inconnue.';
}

// --------------------------------------------------------------------------- echecs a traiter

/// Echecs de livraison en attente de decision. Tout le personnel les voit ; seul un
/// administrateur les traite.
class FailuresSection extends ConsumerWidget {
  const FailuresSection({
    required this.isAdmin,
    required this.onChanged,
    super.key,
  });

  final bool isAdmin;

  /// Appele apres un traitement (la commande peut revenir dans « A attribuer »).
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failures = ref.watch(deliveryFailuresProvider);
    final items = failures.valueOrNull ?? const <DeliveryFailure>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Echecs a traiter (${items.length})',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final failure in items)
            _FailureTile(
              failure: failure,
              isAdmin: isAdmin,
              onResolve: () async {
                final done = await showResolveFailureDialog(context, failure);
                if (done == true) {
                  ref.invalidate(deliveryFailuresProvider);
                  onChanged();
                }
              },
            ),
        ],
      ),
    );
  }
}

class _FailureTile extends StatelessWidget {
  const _FailureTile({
    required this.failure,
    required this.isAdmin,
    required this.onResolve,
  });

  final DeliveryFailure failure;
  final bool isAdmin;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: DsCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Commande #${failure.orderId} - ${failure.reasonLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(formatMoney(failure.total)),
              ],
            ),
            if (failure.deliveryAddress != null)
              Text(
                failure.deliveryAddress!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            if (failure.note != null)
              Text(
                failure.note!,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusBadge(
                  label: failure.customerFault
                      ? 'Faute du client'
                      : 'Faute du restaurant',
                  tone: failure.customerFault
                      ? StatusTone.warning
                      : StatusTone.danger,
                  compact: true,
                ),
                StatusBadge(
                  label: humanStatus(failure.paymentStatus),
                  tone: StatusTone.info,
                  icon: Icons.payments_outlined,
                  compact: true,
                ),
                if (failure.driverName != null)
                  StatusBadge(
                    label: failure.driverName!,
                    tone: StatusTone.neutral,
                    icon: Icons.two_wheeler_outlined,
                    compact: true,
                  ),
                if (failure.callAttempts > 0)
                  StatusBadge(
                    label: '${failure.callAttempts} appel(s)',
                    tone: StatusTone.neutral,
                    icon: Icons.call_outlined,
                    compact: true,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: ValueKey('resolve-failure-${failure.id}'),
                onPressed: isAdmin ? onResolve : null,
                child: Text(
                  isAdmin ? 'Traiter' : 'Reserve a l\'administrateur',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Traitement d'un echec : rembourser, retenir des frais ou relivrer. `true` si l'action est faite.
Future<bool?> showResolveFailureDialog(
  BuildContext context,
  DeliveryFailure failure,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _ResolveDialog(failure: failure),
  );
}

class _ResolveDialog extends ConsumerStatefulWidget {
  const _ResolveDialog({required this.failure});

  final DeliveryFailure failure;

  @override
  ConsumerState<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends ConsumerState<_ResolveDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _action;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String? get _validation => validateResolution(
    widget.failure,
    action: _action,
    amountText: _amount.text,
    note: _note.text,
  );

  Future<void> _submit() async {
    if (_validation != null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final amount = _action == 'retain'
          ? parseSettlementAmount(_amount.text)
          : null;
      await ref
          .read(dispatchRepositoryProvider)
          .resolveFailure(
            widget.failure.id,
            action: _action!,
            amountCents: amount == null ? null : (amount * 100).round(),
            note: _note.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = _apiMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = widget.failure;
    final validation = _validation;
    final guaranteed = failure.paymentStatus == 'guaranteed';
    return AlertDialog(
      title: Text('Traiter l\'echec - commande #${failure.orderId}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${failure.reasonLabel} - ${formatMoney(failure.total)} - '
                '${humanStatus(failure.paymentStatus)}',
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _action,
                onChanged: (value) {
                  if (_submitting) return;
                  setState(() {
                    _action = value;
                    _error = null;
                  });
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      key: const ValueKey('resolve-refund'),
                      value: 'refund',
                      title: const Text('Rembourser le client'),
                      subtitle: Text(
                        guaranteed
                            ? 'L\'empreinte bancaire est liberee, rien n\'est debite'
                            : 'Remboursement total du paiement',
                      ),
                    ),
                    RadioListTile<String>(
                      key: const ValueKey('resolve-retain'),
                      value: 'retain',
                      enabled: failure.customerFault,
                      title: const Text('Retenir des frais'),
                      subtitle: Text(
                        failure.customerFault
                            ? (guaranteed
                                  ? 'Debite ce montant sur l\'empreinte, le reste est libere'
                                  : 'Rembourse le reste, garde ce montant')
                            : 'Impossible : faute du restaurant',
                      ),
                    ),
                    RadioListTile<String>(
                      key: const ValueKey('resolve-redeliver'),
                      value: 'redeliver',
                      enabled: failure.canRedeliver,
                      title: const Text('Relivrer'),
                      subtitle: Text(
                        failure.canRedeliver
                            ? 'La commande revient a attribuer, avec un nouveau code'
                            : 'Impossible : commande plus reglee',
                      ),
                    ),
                  ],
                ),
              ),
              if (_action == 'retain') ...[
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('retain-amount'),
                  controller: _amount,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Montant retenu (EUR)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('resolve-note'),
                controller: _note,
                enabled: !_submitting,
                decoration: InputDecoration(
                  labelText: _action == 'retain'
                      ? 'Motif (obligatoire)'
                      : 'Note (optionnel)',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_action != null && validation != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    validation,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('confirm-resolve'),
          onPressed: _submitting || validation != null ? null : _submit,
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------- livrer sans code

/// Motif d'une livraison sans code (administrateur), ou `null` si on annule.
Future<String?> showDeliverWithoutCodeDialog(
  BuildContext context,
  int orderId,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NoCodeDialog(orderId: orderId),
  );
}

class _NoCodeDialog extends StatefulWidget {
  const _NoCodeDialog({required this.orderId});

  final int orderId;

  @override
  State<_NoCodeDialog> createState() => _NoCodeDialogState();
}

class _NoCodeDialogState extends State<_NoCodeDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _valid => _reason.text.trim().length >= 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Livrer sans code - commande #${widget.orderId}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Le code du client prouve la remise. Sans lui, votre nom et ce motif sont '
            'enregistres dans le journal de la livraison.',
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('no-code-reason'),
            controller: _reason,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Motif (obligatoire)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('confirm-no-code'),
          onPressed: _valid
              ? () => Navigator.pop(context, _reason.text.trim())
              : null,
          child: const Text('Livrer sans code'),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------- reglages

/// Preuve de remise et regles d'echec (administrateur ; lecture seule pour le personnel).
class ProofSettingsCard extends ConsumerWidget {
  const ProofSettingsCard({
    required this.settings,
    required this.isAdmin,
    super.key,
  });

  final DeliverySettings settings;
  final bool isAdmin;

  static const waitOptions = [0, 2, 5, 10, 15, 20, 30, 45, 60];
  static const callOptions = [0, 1, 2, 3, 4, 5];

  Future<void> _update(
    BuildContext context,
    WidgetRef ref, {
    bool? proofRequired,
    int? wait,
    int? calls,
  }) async {
    try {
      await ref
          .read(deliveryRepositoryProvider)
          .updateProofSettings(
            internalEnabled: settings.internalEnabled,
            expectedVersion: settings.version,
            proofRequired: proofRequired,
            failureMinWaitMinutes: wait,
            failureMinCallAttempts: calls,
          );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_apiMessage(error))));
      }
    } finally {
      ref.invalidate(deliverySettingsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        children: [
          SwitchListTile(
            key: const ValueKey('proof-required-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Preuve de remise par code'),
            subtitle: Text(
              settings.deliveryProofRequired
                  ? 'Le livreur doit saisir le code a 4 chiffres du client.'
                  : 'Coupee : le livreur peut livrer sans code. A activer quand l\'app client '
                        'affichant le code est deployee.',
            ),
            value: settings.deliveryProofRequired,
            onChanged: isAdmin
                ? (value) => _update(context, ref, proofRequired: value)
                : null,
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Client absent ou injoignable (regles generales)'),
            subtitle: Text(
              'Valables pour tous les etablissements, sauf reglage propre a un '
              'etablissement. Avant de declarer l\'echec, le livreur doit avoir :',
            ),
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('failure-wait'),
                  initialValue:
                      waitOptions.contains(settings.failureMinWaitMinutes)
                      ? settings.failureMinWaitMinutes
                      : null,
                  decoration: const InputDecoration(labelText: 'Attendu (min)'),
                  items: [
                    for (final value in waitOptions)
                      DropdownMenuItem(value: value, child: Text('$value min')),
                  ],
                  onChanged: isAdmin
                      ? (value) => _update(context, ref, wait: value)
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('failure-calls'),
                  initialValue:
                      callOptions.contains(settings.failureMinCallAttempts)
                      ? settings.failureMinCallAttempts
                      : null,
                  decoration: const InputDecoration(labelText: 'Appels'),
                  items: [
                    for (final value in callOptions)
                      DropdownMenuItem(
                        value: value,
                        child: Text('$value appel(s)'),
                      ),
                  ],
                  onChanged: isAdmin
                      ? (value) => _update(context, ref, calls: value)
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
