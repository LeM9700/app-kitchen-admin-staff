import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/payments/presentation/guarantee_settlement_dialog.dart'
    show parseSettlementAmount;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// --------------------------------------------------------------------------- aides pures

final _codePattern = RegExp(r'^\d{4}$');

/// Code de remise : exactement 4 chiffres (meme regle que l'API).
bool isValidDeliveryCode(String raw) => _codePattern.hasMatch(raw.trim());

/// Especes recues saisies par le livreur : au moins le montant du, sinon `null`.
double? validCashReceived(String raw, double amountDue) {
  final value = parseSettlementAmount(raw);
  if (value == null || value < amountDue) return null;
  return value;
}

/// Motifs d'echec proposes au livreur, dans l'ordre d'affichage : (code API, libelle).
const failureReasons = <(String, String)>[
  ('customer_absent', 'Client absent'),
  ('customer_unreachable', 'Client injoignable'),
  ('wrong_address', 'Adresse introuvable ou fausse'),
  ('customer_refused', 'Client a refuse la commande'),
  ('order_problem', 'Probleme avec la commande'),
  ('other', 'Autre'),
];

const _waitingReasons = {'customer_absent', 'customer_unreachable'};

/// Pourquoi l'echec ne peut pas encore etre declare, ou `null` s'il le peut.
///
/// Reprend les regles de l'API pour eviter un aller-retour (l'API reste l'autorite) :
/// « absent » et « injoignable » exigent d'avoir signale son arrivee, attendu et appele.
String? failureBlockReason(
  DriverDelivery delivery,
  String reason, {
  required int callAttempts,
  required DateTime now,
  String note = '',
}) {
  if (reason == 'other' && note.trim().length < 3) {
    return 'Precisez le motif.';
  }
  if (!_waitingReasons.contains(reason)) return null;
  final arrivedAt = delivery.arrivedAt;
  if (delivery.phase != 'arrived' || arrivedAt == null) {
    return 'Signalez d\'abord votre arrivee (bouton « Arrive »).';
  }
  final waited = now.difference(arrivedAt);
  final needed = Duration(minutes: delivery.failureMinWaitMinutes);
  if (waited < needed) {
    final remaining = needed - waited;
    final minutes = (remaining.inSeconds / 60).ceil();
    return 'Attendez encore $minutes min avant de declarer l\'echec.';
  }
  if (callAttempts < delivery.failureMinCallAttempts) {
    return 'Appelez le client au moins ${delivery.failureMinCallAttempts} fois '
        '($callAttempts fait).';
  }
  return null;
}

// --------------------------------------------------------------------------- remise

class DeliveryProofInput {
  const DeliveryProofInput({this.code, this.cash});

  final String? code;
  final double? cash;
}

/// Validation de la remise : code du client (si exige), puis especes a encaisser (si dues).
/// Retourne `null` si le livreur annule.
Future<DeliveryProofInput?> showDeliveryProofDialog(
  BuildContext context,
  DriverDelivery delivery,
) {
  return showDialog<DeliveryProofInput>(
    context: context,
    builder: (context) => _ProofDialog(delivery: delivery),
  );
}

class _ProofDialog extends StatefulWidget {
  const _ProofDialog({required this.delivery});

  final DriverDelivery delivery;

  @override
  State<_ProofDialog> createState() => _ProofDialogState();
}

class _ProofDialogState extends State<_ProofDialog> {
  late final TextEditingController _cash = TextEditingController(
    text: widget.delivery.amountDue.toStringAsFixed(2),
  );
  final TextEditingController _code = TextEditingController();

  @override
  void dispose() {
    _cash.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _needsCode => widget.delivery.proofRequired;
  bool get _needsCash => widget.delivery.amountDue > 0;

  double? get _cashValue => validCashReceived(_cash.text, widget.delivery.amountDue);

  bool get _valid =>
      (!_needsCode || isValidDeliveryCode(_code.text)) &&
      (!_needsCash || _cashValue != null);

  @override
  Widget build(BuildContext context) {
    final delivery = widget.delivery;
    if (delivery.codeLocked) {
      return AlertDialog(
        title: Text('Commande #${delivery.orderId} verrouillee'),
        content: const Text(
          'Trop de codes incorrects. Contactez le restaurant : un administrateur peut '
          'conclure cette livraison.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      );
    }
    final due = delivery.amountDue;
    final cash = _cashValue;
    return AlertDialog(
      title: Text(
        _needsCash
            ? 'Encaisser ${formatMoney(due)}'
            : 'Livrer la commande #${delivery.orderId} ?',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_needsCode) ...[
              const Text('Demandez au client son code de remise a 4 chiffres.'),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('delivery-code'),
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Code du client',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
            ],
            if (_needsCash) ...[
              Text('Commande #${delivery.orderId} : a regler en especes a la remise.'),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('cash-received'),
                controller: _cash,
                autofocus: !_needsCode,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Especes recues',
                  suffixText: 'EUR',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              if (cash == null)
                Text(
                  'Montant insuffisant ou invalide',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else
                Text(
                  'A rendre : ${formatMoney(cash - due)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
            ] else if (!_needsCode)
              const Text('Deja payee : rien a encaisser.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('confirm-delivered'),
          onPressed: _valid
              ? () => Navigator.pop(
                    context,
                    DeliveryProofInput(
                      code: _needsCode ? _code.text.trim() : null,
                      cash: _needsCash ? cash : null,
                    ),
                  )
              : null,
          child: Text(_needsCash ? 'Encaisse et livree' : 'Livree'),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------- echec

class FailureInput {
  const FailureInput({required this.reason, this.note});

  final String reason;
  final String? note;
}

/// Declaration d'un echec de livraison. [callAttempts] : appels deja passes depuis cet ecran.
/// Retourne `null` si le livreur annule.
Future<FailureInput?> showFailureDialog(
  BuildContext context,
  DriverDelivery delivery, {
  required int callAttempts,
  DateTime? now,
}) {
  return showDialog<FailureInput>(
    context: context,
    builder: (context) => _FailureDialog(
      delivery: delivery,
      callAttempts: callAttempts,
      now: now ?? DateTime.now(),
    ),
  );
}

class _FailureDialog extends StatefulWidget {
  const _FailureDialog({
    required this.delivery,
    required this.callAttempts,
    required this.now,
  });

  final DriverDelivery delivery;
  final int callAttempts;
  final DateTime now;

  @override
  State<_FailureDialog> createState() => _FailureDialogState();
}

class _FailureDialogState extends State<_FailureDialog> {
  final TextEditingController _note = TextEditingController();
  String? _reason;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String? get _block => _reason == null
      ? 'Choisissez un motif.'
      : failureBlockReason(
          widget.delivery,
          _reason!,
          callAttempts: widget.callAttempts,
          now: widget.now,
          note: _note.text,
        );

  @override
  Widget build(BuildContext context) {
    final block = _block;
    return AlertDialog(
      title: Text('Echec de livraison - commande #${widget.delivery.orderId}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<String>(
                groupValue: _reason,
                onChanged: (value) => setState(() => _reason = value),
                child: Column(
                  children: [
                    for (final (code, label) in failureReasons)
                      RadioListTile<String>(
                        key: ValueKey('failure-$code'),
                        value: code,
                        title: Text(label),
                        dense: true,
                      ),
                  ],
                ),
              ),
              TextField(
                key: const ValueKey('failure-note'),
                controller: _note,
                decoration: InputDecoration(
                  labelText: _reason == 'other'
                      ? 'Precision (obligatoire)'
                      : 'Precision (optionnel)',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text('Appels passes au client : ${widget.callAttempts}'),
              if (_reason != null && block != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    block,
                    key: const ValueKey('failure-block'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('confirm-failure'),
          onPressed: block == null
              ? () => Navigator.pop(
                    context,
                    FailureInput(reason: _reason!, note: _note.text.trim()),
                  )
              : null,
          child: const Text('Declarer l\'echec'),
        ),
      ],
    );
  }
}
