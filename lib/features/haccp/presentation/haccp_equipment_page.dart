import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_ui.dart';
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
  Object? _error;

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
      if (mounted) setState(() => _error = e);
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
          SnackBar(
            content: Text(
              haccpFriendlyError(e, 'Enregistrement impossible'),
            ),
            backgroundColor: haccpToneStyle(HaccpTone.danger).foreground,
          ),
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
          SnackBar(
            content: Text(
              haccpFriendlyError(e, 'Enregistrement impossible'),
            ),
            backgroundColor: haccpToneStyle(HaccpTone.danger).foreground,
          ),
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
    final equipment = _equipment ?? const <HaccpEquipment>[];
    return Scaffold(
      backgroundColor: HaccpPalette.background,
      appBar: AppBar(
        title: const Text('Équipements HACCP'),
        backgroundColor: HaccpPalette.background,
        foregroundColor: HaccpPalette.graphite,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un équipement'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: _loading
              ? const HaccpSkeleton()
              : _error != null
                  ? HaccpErrorState(
                      message: haccpFriendlyError(
                        _error!,
                        'Impossible de charger les équipements',
                      ),
                      onRetry: _load,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: equipment.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: AppSpacing.xl),
                                HaccpEmptyState(
                                  icon: Icons.kitchen_outlined,
                                  title: 'Aucun équipement',
                                  message:
                                      'Ajoutez un frigo, un congélateur ou une chambre froide.',
                                ),
                              ],
                            )
                          : _buildList(equipment),
                    ),
        ),
      ),
    );
  }

  Widget _buildList(List<HaccpEquipment> equipment) {
    final activeCount = equipment.where((e) => e.isActive).length;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        96,
      ),
      children: [
        HaccpPageHeader(
          title: 'Équipements',
          subtitle: '$activeCount actif(s) sur ${equipment.length}',
          icon: Icons.kitchen_outlined,
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 2 : 1;
            final width =
                (constraints.maxWidth - (columns - 1) * AppSpacing.sm) /
                    columns;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final e in equipment)
                  SizedBox(
                    width: width,
                    child: _EquipmentCard(
                      equipment: e,
                      typeLabel: _typeLabel(e.type),
                      onTap: () => _openForm(existing: e),
                      onToggle: () => _toggleActive(e),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({
    required this.equipment,
    required this.typeLabel,
    required this.onTap,
    required this.onToggle,
  });

  final HaccpEquipment equipment;
  final String typeLabel;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final e = equipment;
    final location = e.location;
    final hasRange = e.targetMinTemp != null && e.targetMaxTemp != null;
    final checks = [
      if (e.checkAtOpening) 'ouverture',
      if (e.checkAtClosing) 'fermeture',
    ];
    final lines = [
      [
        typeLabel,
        if (location != null && location.isNotEmpty) location,
      ].join(' • '),
      if (hasRange) 'Plage cible ${e.tempRangeLabel}',
      if (checks.isNotEmpty) 'Contrôlé à ${checks.join(' et ')}',
    ];
    return Material(
      color: HaccpPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: HaccpPalette.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: HaccpPalette.surfaceWarm,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.kitchen_outlined,
                  color: e.isActive
                      ? HaccpPalette.graphite
                      : HaccpPalette.graphiteSoft,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name,
                      style: TextStyle(
                        color: e.isActive
                            ? HaccpPalette.graphite
                            : HaccpPalette.graphiteSoft,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        decoration:
                            e.isActive ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          line,
                          style: const TextStyle(
                            color: HaccpPalette.graphiteSoft,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (!e.isActive)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: HaccpStatusBadge(
                          label: 'Inactif',
                          tone: HaccpTone.neutral,
                          compact: true,
                        ),
                      ),
                  ],
                ),
              ),
              Switch(value: e.isActive, onChanged: (_) => onToggle()),
            ],
          ),
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
      title: Text(
        widget.existing == null
            ? 'Nouvel équipement'
            : 'Modifier l\'équipement',
      ),
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
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'fridge', child: Text('Frigo')),
                  DropdownMenuItem(
                    value: 'freezer',
                    child: Text('Congélateur'),
                  ),
                  DropdownMenuItem(
                    value: 'cold_room',
                    child: Text('Chambre froide'),
                  ),
                  DropdownMenuItem(
                    value: 'hot_hold',
                    child: Text('Maintien au chaud'),
                  ),
                  DropdownMenuItem(
                    value: 'ambient',
                    child: Text('Température ambiante'),
                  ),
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
                title: const Text(
                  'Contrôlé à l\'ouverture',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              SwitchListTile(
                dense: true,
                value: _checkAtClosing,
                onChanged: (v) => setState(() => _checkAtClosing = v),
                title: const Text(
                  'Contrôlé à la fermeture',
                  style: TextStyle(fontSize: 13),
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
