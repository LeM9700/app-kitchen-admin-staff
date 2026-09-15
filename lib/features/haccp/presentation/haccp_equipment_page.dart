import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Gestion des équipements HACCP (frigos, congélateurs, chambres froides...).
///
/// Backend déjà prêt (GET/POST/PATCH /haccp/equipment) -- cette page était
/// jusqu'ici la seule pièce manquante : aucun écran ne permettait d'en
/// ajouter depuis l'app.
class HaccpEquipmentPage extends ConsumerStatefulWidget {
  const HaccpEquipmentPage({super.key});

  @override
  ConsumerState<HaccpEquipmentPage> createState() => _HaccpEquipmentPageState();
}

class _HaccpEquipmentPageState extends ConsumerState<HaccpEquipmentPage> {
  List<HaccpEquipment>? _equipment;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final equipment = await ref
          .read(haccpRepositoryProvider)
          .listEquipment(activeOnly: false);
      if (mounted) setState(() => _equipment = equipment);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({HaccpEquipment? existing}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EquipmentFormDialog(existing: existing),
    );
    if (result == null) return;

    try {
      if (existing == null) {
        await ref.read(haccpRepositoryProvider).createEquipment(result);
      } else {
        await ref
            .read(haccpRepositoryProvider)
            .updateEquipment(existing.id, result);
      }
      ref.invalidate(haccpEquipmentProvider);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleActive(HaccpEquipment equipment) async {
    try {
      await ref
          .read(haccpRepositoryProvider)
          .updateEquipment(equipment.id, {'is_active': !equipment.isActive});
      ref.invalidate(haccpEquipmentProvider);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'fridge':
        return 'Frigo';
      case 'freezer':
        return 'Congélateur';
      case 'cold_room':
        return 'Chambre froide';
      case 'hot_hold':
        return 'Maintien au chaud';
      case 'ambient':
        return 'Température ambiante';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Équipements HACCP')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Erreur : $_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: (_equipment ?? const []).isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Text(
                                'Aucun équipement. Appuyez sur + pour en ajouter un '
                                '(frigo, congélateur...).',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _equipment!.length,
                          itemBuilder: (context, index) {
                            final e = _equipment![index];
                            return ListTile(
                              leading: Icon(
                                Icons.kitchen_outlined,
                                color: e.isActive ? null : Colors.grey,
                              ),
                              title: Text(
                                e.name,
                                style: TextStyle(
                                  color: e.isActive ? null : Colors.grey,
                                  decoration: e.isActive
                                      ? null
                                      : TextDecoration.lineThrough,
                                ),
                              ),
                              subtitle: Text(
                                '${_typeLabel(e.type)}'
                                '${e.location != null ? ' • ${e.location}' : ''}'
                                '${e.tempRangeLabel.isNotEmpty ? ' • ${e.tempRangeLabel}' : ''}',
                              ),
                              onTap: () => _openForm(existing: e),
                              trailing: Switch(
                                value: e.isActive,
                                onChanged: (_) => _toggleActive(e),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

class _EquipmentFormDialog extends StatefulWidget {
  const _EquipmentFormDialog({this.existing});

  final HaccpEquipment? existing;

  @override
  State<_EquipmentFormDialog> createState() => _EquipmentFormDialogState();
}

class _EquipmentFormDialogState extends State<_EquipmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _minTempController;
  late final TextEditingController _maxTempController;
  late String _type;
  late bool _checkAtOpening;
  late bool _checkAtClosing;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _locationController = TextEditingController(text: e?.location ?? '');
    _minTempController =
        TextEditingController(text: e?.targetMinTemp?.toString() ?? '');
    _maxTempController =
        TextEditingController(text: e?.targetMaxTemp?.toString() ?? '');
    _type = e?.type ?? 'fridge';
    _checkAtOpening = e?.checkAtOpening ?? true;
    _checkAtClosing = e?.checkAtClosing ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _minTempController.dispose();
    _maxTempController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Nouvel équipement'
          : 'Modifier l\'équipement'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Champ obligatoire' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'fridge', child: Text('Frigo')),
                  DropdownMenuItem(
                      value: 'freezer', child: Text('Congélateur')),
                  DropdownMenuItem(
                      value: 'cold_room', child: Text('Chambre froide')),
                  DropdownMenuItem(
                      value: 'hot_hold', child: Text('Maintien au chaud')),
                  DropdownMenuItem(
                      value: 'ambient', child: Text('Température ambiante')),
                ],
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Emplacement (optionnel)',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minTempController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Temp. min (°C)',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _maxTempController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Temp. max (°C)',
                      ),
                      validator: (v) {
                        final min = double.tryParse(_minTempController.text);
                        final max =
                            v == null || v.isEmpty ? null : double.tryParse(v);
                        if (min != null && max != null && max <= min) {
                          return 'Doit être > temp. min';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                dense: true,
                value: _checkAtOpening,
                onChanged: (v) => setState(() => _checkAtOpening = v),
                title: const Text('Contrôlé à l\'ouverture',
                    style: TextStyle(fontSize: 13)),
              ),
              SwitchListTile(
                dense: true,
                value: _checkAtClosing,
                onChanged: (v) => setState(() => _checkAtClosing = v),
                title: const Text('Contrôlé à la fermeture',
                    style: TextStyle(fontSize: 13)),
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
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, {
              'name': _nameController.text.trim(),
              'type': _type,
              'location': _locationController.text.trim().isNotEmpty
                  ? _locationController.text.trim()
                  : null,
              'target_min_temp': _minTempController.text.trim().isNotEmpty
                  ? double.tryParse(_minTempController.text.trim())
                  : null,
              'target_max_temp': _maxTempController.text.trim().isNotEmpty
                  ? double.tryParse(_maxTempController.text.trim())
                  : null,
              'check_at_opening': _checkAtOpening,
              'check_at_closing': _checkAtClosing,
            });
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
