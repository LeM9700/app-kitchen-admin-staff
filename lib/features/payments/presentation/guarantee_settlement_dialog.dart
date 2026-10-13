import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/features/orders/presentation/delivery_failure_dialog.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Comment l'empreinte bancaire d'une livraison est reglee.
enum GuaranteeSettlement {
  /// Le client a paye en especes : l'empreinte est liberee, l'encaissement enregistre.
  cash,

  /// La carte du client est debitee en totalite (administrateur).
  card,

  /// Frais debites apres un echec de livraison du fait du client (administrateur).
  fee,

  /// Rien n'est debite : l'empreinte est liberee.
  release,
}

/// Montant saisi (virgule ou point) en euros, ou `null` s'il est vide ou invalide.
double? parseSettlementAmount(String raw) {
  final normalized = raw.trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return null;
  }
  final value = double.tryParse(normalized);
  if (value == null || value.isNaN || value.isInfinite || value <= 0) {
    return null;
  }
  return value;
}

/// Message d'erreur de saisie, ou `null` si le choix peut etre envoye.
///
/// Memes regles que l'API (`payments/guarantee.py`) pour ne pas aller-retour
/// inutilement : especes >= total, frais > 0 et <= empreinte, motif obligatoire.
String? validateSettlement({
  required GuaranteeSettlement choice,
  required double total,
  required String amountText,
  required String reason,
}) {
  switch (choice) {
    case GuaranteeSettlement.cash:
      final received = parseSettlementAmount(amountText);
      if (amountText.trim().isNotEmpty && received == null) {
        return 'Montant recu invalide';
      }
      if (received != null && received < total) {
        return 'Montant recu inferieur au total de la commande';
      }
      return null;
    case GuaranteeSettlement.card:
    case GuaranteeSettlement.release:
      return null;
    case GuaranteeSettlement.fee:
      final fee = parseSettlementAmount(amountText);
      if (fee == null) {
        return 'Montant a debiter requis';
      }
      if (fee > total) {
        return 'Le montant depasse l\'empreinte (${formatMoney(total)})';
      }
      if (reason.trim().isEmpty) {
        return 'Un motif est requis pour debiter la carte';
      }
      return null;
  }
}

/// Regle l'empreinte bancaire d'une commande `guaranteed`.
///
/// Retourne `true` quand le reglement a ete enregistre cote API (la commande
/// peut alors etre marquee livree), `false` si l'utilisateur annule.
Future<bool> showGuaranteeSettlementDialog(
  BuildContext context, {
  required int orderId,
  required double total,
}) async {
  final settled = await showDialog<bool>(
    context: context,
    builder: (context) =>
        _GuaranteeSettlementDialog(orderId: orderId, total: total),
  );
  return settled ?? false;
}

class _GuaranteeSettlementDialog extends ConsumerStatefulWidget {
  const _GuaranteeSettlementDialog({
    required this.orderId,
    required this.total,
  });

  final int orderId;
  final double total;

  @override
  ConsumerState<_GuaranteeSettlementDialog> createState() =>
      _GuaranteeSettlementDialogState();
}

class _GuaranteeSettlementDialogState
    extends ConsumerState<_GuaranteeSettlementDialog> {
  final _amount = TextEditingController();
  final _details = TextEditingController();
  GuaranteeSettlement? _choice;
  String _reason = deliveryFailureReasons.first;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _details.dispose();
    super.dispose();
  }

  String get _composedReason =>
      composeDeliveryFailureNote(_reason, _details.text);

  String? get _validation => _choice == null
      ? 'Choisissez comment regler l\'empreinte'
      : validateSettlement(
          choice: _choice!,
          total: widget.total,
          amountText: _amount.text,
          reason: _composedReason,
        );

  Future<void> _submit() async {
    final choice = _choice;
    if (choice == null || _validation != null || _submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(paymentsRepositoryProvider);
    try {
      switch (choice) {
        case GuaranteeSettlement.cash:
          await repo.guaranteeCashCollected(
            widget.orderId,
            amountReceived: parseSettlementAmount(_amount.text),
          );
        case GuaranteeSettlement.card:
          await repo.captureGuarantee(
            widget.orderId,
            reason: 'Paiement carte a la livraison',
          );
        case GuaranteeSettlement.fee:
          final fee = parseSettlementAmount(_amount.text)!;
          await repo.captureGuarantee(
            widget.orderId,
            amountCents: (fee * 100).round(),
            reason: _composedReason,
          );
        case GuaranteeSettlement.release:
          await repo.releaseGuarantee(
            widget.orderId,
            reason: 'released_by_staff',
          );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error is ApiError
              ? error.message
              : 'Reglement impossible pour le moment. Reessayez.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(currentPermissionSetProvider).hasRole('admin');
    final validation = _validation;
    return AlertDialog(
      title: Text('Regler l\'empreinte - commande #${widget.orderId}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Une empreinte de ${formatMoney(widget.total)} est posee sur la '
                'carte du client. Rien n\'est debite tant que vous ne le '
                'choisissez pas.',
              ),
              const SizedBox(height: 12),
              RadioGroup<GuaranteeSettlement>(
                groupValue: _choice,
                onChanged: (value) {
                  if (_submitting) return;
                  setState(() {
                    _choice = value;
                    _error = null;
                  });
                },
                child: Column(
                  children: [
                    const RadioListTile<GuaranteeSettlement>(
                      value: GuaranteeSettlement.cash,
                      title: Text('Especes encaissees'),
                      subtitle: Text('L\'empreinte est liberee'),
                    ),
                    RadioListTile<GuaranteeSettlement>(
                      value: GuaranteeSettlement.card,
                      enabled: isAdmin,
                      title: const Text('Debiter la carte (total)'),
                      subtitle: Text(
                        isAdmin
                            ? 'Paiement carte a la livraison'
                            : 'Reserve a l\'administrateur',
                      ),
                    ),
                    RadioListTile<GuaranteeSettlement>(
                      value: GuaranteeSettlement.fee,
                      enabled: isAdmin,
                      title: const Text('Debiter des frais (echec client)'),
                      subtitle: Text(
                        isAdmin
                            ? 'Montant libre, le reste est libere'
                            : 'Reserve a l\'administrateur',
                      ),
                    ),
                    const RadioListTile<GuaranteeSettlement>(
                      value: GuaranteeSettlement.release,
                      title: Text('Liberer sans debit'),
                      subtitle: Text('Rien n\'est debite'),
                    ),
                  ],
                ),
              ),
              if (_choice == GuaranteeSettlement.cash ||
                  _choice == GuaranteeSettlement.fee) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _amount,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _choice == GuaranteeSettlement.cash
                        ? 'Montant recu (optionnel)'
                        : 'Montant a debiter (EUR)',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (_choice == GuaranteeSettlement.fee) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _reason,
                  decoration: const InputDecoration(
                    labelText: 'Motif',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final reason in deliveryFailureReasons)
                      DropdownMenuItem(value: reason, child: Text(reason)),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _reason = value ?? _reason),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _details,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Precision (optionnel)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (_choice != null && validation != null) ...[
                const SizedBox(height: 8),
                Text(
                  validation,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
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
          onPressed: _submitting || validation != null ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirmer'),
        ),
      ],
    );
  }
}
