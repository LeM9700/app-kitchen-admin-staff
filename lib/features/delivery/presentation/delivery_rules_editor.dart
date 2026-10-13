import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:flutter/material.dart';

const _dayLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// Liste editable des regles de tarification d'une zone (livraison offerte des X EUR, tarif du
/// soir, jours ou periodes particuliers...). Les regles sont evaluees cote serveur.
class DeliveryRulesEditor extends StatelessWidget {
  const DeliveryRulesEditor({
    required this.rules,
    required this.onChanged,
    super.key,
  });

  final List<DeliveryZoneRule> rules;
  final ValueChanged<List<DeliveryZoneRule>> onChanged;

  static const maxRules = 20;

  Future<void> _edit(BuildContext context, {int? index}) async {
    final result = await showDialog<DeliveryZoneRule>(
      context: context,
      builder: (context) =>
          _RuleDialog(rule: index == null ? null : rules[index]),
    );
    if (result == null) return;
    final next = [...rules];
    if (index == null) {
      next.add(result);
    } else {
      next[index] = result;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Regles de tarification',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('zone-add-rule'),
              onPressed: rules.length >= maxRules ? null : () => _edit(context),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une regle'),
            ),
          ],
        ),
        if (rules.isEmpty)
          Text(
            'Aucune regle : le tarif de la zone s\'applique toujours. Ajoutez par '
            'exemple « Livraison offerte des 25 » ou un tarif du soir.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (var i = 0; i < rules.length; i++)
          Card(
            key: ValueKey('zone-rule-$i'),
            margin: const EdgeInsets.only(top: AppSpacing.xs),
            child: ListTile(
              dense: true,
              leading: Icon(
                rules[i].isFree
                    ? Icons.card_giftcard_outlined
                    : Icons.price_change_outlined,
              ),
              title: Text(rules[i].label),
              subtitle: Text(rules[i].describe(formatMoney)),
              onTap: () => _edit(context, index: i),
              trailing: IconButton(
                tooltip: 'Supprimer la regle',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onChanged([...rules]..removeAt(i)),
              ),
            ),
          ),
      ],
    );
  }
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({this.rule});

  final DeliveryZoneRule? rule;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final TextEditingController _label;
  late final TextEditingController _fee;
  late final TextEditingController _minSubtotal;
  late final TextEditingController _priority;
  late String _kind;
  late Set<int> _days;
  TimeOfDay? _start;
  TimeOfDay? _end;
  String? _startsOn;
  String? _endsOn;
  String? _error;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _label = TextEditingController(text: rule?.label ?? '');
    _fee = TextEditingController(text: rule?.fee?.toString() ?? '');
    _minSubtotal = TextEditingController(
      text: rule?.minSubtotal?.toString() ?? '',
    );
    _priority = TextEditingController(text: (rule?.priority ?? 0).toString());
    _kind = rule?.kind ?? DeliveryZoneRule.kindFree;
    _days = {...?rule?.daysOfWeek};
    _start = _parseTime(rule?.startTime);
    _end = _parseTime(rule?.endTime);
    _startsOn = rule?.startsOn;
    _endsOn = rule?.endsOn;
  }

  @override
  void dispose() {
    _label.dispose();
    _fee.dispose();
    _minSubtotal.dispose();
    _priority.dispose();
    super.dispose();
  }

  static TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    return hour == null || minute == null
        ? null
        : TimeOfDay(hour: hour, minute: minute);
  }

  static String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  double? _number(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          (start ? _start : _end) ?? const TimeOfDay(hour: 19, minute: 0),
    );
    if (picked == null) return;
    setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() {
      _startsOn = _formatDate(picked.start);
      _endsOn = _formatDate(picked.end);
    });
  }

  void _submit() {
    final label = _label.text.trim();
    final fee = _number(_fee.text);
    final min = _minSubtotal.text.trim().isEmpty
        ? null
        : _number(_minSubtotal.text);
    final priority = int.tryParse(_priority.text.trim()) ?? 0;
    String? error;
    if (label.isEmpty) {
      error = 'Nom de la regle obligatoire';
    } else if (_kind == DeliveryZoneRule.kindFee && (fee == null || fee < 0)) {
      error = 'Tarif invalide';
    } else if (_minSubtotal.text.trim().isNotEmpty &&
        (min == null || min < 0)) {
      error = 'Montant de panier invalide';
    } else if ((_start == null) != (_end == null)) {
      error = 'Indiquez l\'heure de debut ET de fin';
    } else if (_start != null && _start == _end) {
      error = 'Debut et fin ne peuvent pas etre identiques';
    } else if (priority < 0 || priority > 100) {
      error = 'Priorite entre 0 et 100';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      DeliveryZoneRule(
        id: widget.rule?.id,
        label: label,
        kind: _kind,
        fee: _kind == DeliveryZoneRule.kindFee ? fee : null,
        minSubtotal: min,
        daysOfWeek: (_days.toList()..sort()),
        startTime: _start == null ? null : _formatTime(_start!),
        endTime: _end == null ? null : _formatTime(_end!),
        startsOn: _startsOn,
        endsOn: _endsOn,
        priority: priority,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rule == null ? 'Nouvelle regle' : 'Modifier la regle'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('rule-label'),
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Nom (ex. Offerte des 25)',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<String>(
                key: const ValueKey('rule-kind'),
                segments: const [
                  ButtonSegment(
                    value: DeliveryZoneRule.kindFree,
                    label: Text('Livraison offerte'),
                    icon: Icon(Icons.card_giftcard_outlined),
                  ),
                  ButtonSegment(
                    value: DeliveryZoneRule.kindFee,
                    label: Text('Autre tarif'),
                    icon: Icon(Icons.price_change_outlined),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (value) =>
                    setState(() => _kind = value.first),
              ),
              if (_kind == DeliveryZoneRule.kindFee) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const ValueKey('rule-fee'),
                  controller: _fee,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tarif de livraison',
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('rule-min-subtotal'),
                controller: _minSubtotal,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'A partir d\'un panier de (optionnel)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Jours (aucun = tous les jours)',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (var d = 0; d < 7; d++)
                    FilterChip(
                      key: ValueKey('rule-day-$d'),
                      label: Text(_dayLabels[d]),
                      selected: _days.contains(d),
                      onSelected: (on) =>
                          setState(() => on ? _days.add(d) : _days.remove(d)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('rule-start-time'),
                      onPressed: () => _pickTime(start: true),
                      child: Text(
                        _start == null
                            ? 'Heure de debut'
                            : _formatTime(_start!),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('rule-end-time'),
                      onPressed: () => _pickTime(start: false),
                      child: Text(
                        _end == null ? 'Heure de fin' : _formatTime(_end!),
                      ),
                    ),
                  ),
                  if (_start != null || _end != null)
                    IconButton(
                      tooltip: 'Toute la journee',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _start = null;
                        _end = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('rule-dates'),
                      onPressed: _pickDates,
                      icon: const Icon(Icons.date_range_outlined),
                      label: Text(
                        _startsOn == null && _endsOn == null
                            ? 'Toute l\'annee'
                            : '${_startsOn ?? '...'} → ${_endsOn ?? '...'}',
                      ),
                    ),
                  ),
                  if (_startsOn != null || _endsOn != null)
                    IconButton(
                      tooltip: 'Toute l\'annee',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _startsOn = null;
                        _endsOn = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('rule-priority'),
                controller: _priority,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText:
                      'Priorite (0-100, la plus haute gagne entre deux tarifs)',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  key: const ValueKey('rule-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
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
          key: const ValueKey('rule-save'),
          onPressed: _submit,
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
