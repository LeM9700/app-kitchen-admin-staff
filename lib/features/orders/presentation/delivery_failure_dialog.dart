import 'package:flutter/material.dart';

/// Motifs proposes pour un echec de livraison. Le libelle choisi (complete par le
/// texte libre) est envoye comme `note` : l'API exige un motif non vide.
const deliveryFailureReasons = <String>[
  'Client absent',
  'Adresse introuvable ou fausse',
  'Client injoignable',
  'Client a refuse la commande',
  'Autre',
];

/// Compose la note envoyee a l'API a partir du motif et du detail libre.
String composeDeliveryFailureNote(String reason, String details) {
  final trimmed = details.trim();
  return trimmed.isEmpty ? reason : '$reason - $trimmed';
}

/// Demande le motif d'un echec de livraison. Retourne la note a envoyer, ou
/// `null` si l'utilisateur annule.
Future<String?> showDeliveryFailureDialog(
  BuildContext context,
  int orderId,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => _DeliveryFailureDialog(orderId: orderId),
  );
}

class _DeliveryFailureDialog extends StatefulWidget {
  const _DeliveryFailureDialog({required this.orderId});

  final int orderId;

  @override
  State<_DeliveryFailureDialog> createState() => _DeliveryFailureDialogState();
}

class _DeliveryFailureDialogState extends State<_DeliveryFailureDialog> {
  final _details = TextEditingController();
  String? _reason;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  bool get _needsDetails => _reason == 'Autre';

  bool get _canSubmit =>
      _reason != null && (!_needsDetails || _details.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Echec de livraison - commande #${widget.orderId}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Le client sera prevenu. La commande passera en echec de '
                'livraison : un remboursement ou une nouvelle tentative '
                'devra etre decide ensuite.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in deliveryFailureReasons)
                    ChoiceChip(
                      key: ValueKey('delivery-failure-reason-$reason'),
                      label: Text(reason),
                      selected: _reason == reason,
                      onSelected: (_) => setState(() => _reason = reason),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('delivery-failure-details'),
                controller: _details,
                onChanged: (_) => setState(() {}),
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: _needsDetails ? 'Precisez' : 'Details (optionnel)',
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
          key: const ValueKey('delivery-failure-confirm'),
          onPressed: _canSubmit
              ? () => Navigator.pop(
                    context,
                    composeDeliveryFailureNote(_reason!, _details.text),
                  )
              : null,
          child: const Text('Declarer l\'echec'),
        ),
      ],
    );
  }
}
