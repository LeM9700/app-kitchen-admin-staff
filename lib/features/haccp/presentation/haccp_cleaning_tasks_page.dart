import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Gestion du plan de nettoyage & désinfection (tâches ND).
///
/// Backend déjà prêt (GET/POST/PATCH /haccp/cleaning-tasks) -- cette page
/// était la pièce manquante : aucun écran ne permettait d'en ajouter.
class HaccpCleaningTasksPage extends ConsumerStatefulWidget {
  const HaccpCleaningTasksPage({super.key});

  @override
  ConsumerState<HaccpCleaningTasksPage> createState() =>
      _HaccpCleaningTasksPageState();
}

class _HaccpCleaningTasksPageState
    extends ConsumerState<HaccpCleaningTasksPage> {
  List<HaccpCleaningTask>? _tasks;
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
      final tasks = await ref.read(haccpRepositoryProvider).listCleaningTasks();
      if (mounted) setState(() => _tasks = tasks);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({HaccpCleaningTask? existing}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CleaningTaskFormDialog(existing: existing),
    );
    if (result == null) return;

    try {
      if (existing == null) {
        await ref.read(haccpRepositoryProvider).createCleaningTask(result);
      } else {
        await ref
            .read(haccpRepositoryProvider)
            .updateCleaningTask(existing.id, result);
      }
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

  Future<void> _toggleActive(HaccpCleaningTask task) async {
    try {
      await ref
          .read(haccpRepositoryProvider)
          .updateCleaningTask(task.id, {'is_active': !task.isActive});
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

  String _frequencyLabel(String f) {
    switch (f) {
      case 'daily':
        return 'Quotidien';
      case 'weekly':
        return 'Hebdomadaire';
      case 'monthly':
        return 'Mensuel';
      case 'per_service':
        return 'Par service';
      default:
        return f;
    }
  }

  String _sessionTypeLabel(String s) {
    switch (s) {
      case 'opening':
        return 'Avant ouverture';
      case 'closing':
        return 'Avant fermeture';
      default:
        return 'Ouverture + Fermeture';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks ?? const <HaccpCleaningTask>[];
    return Scaffold(
      backgroundColor: HaccpPalette.background,
      appBar: AppBar(
        title: const Text('Plan de nettoyage & désinfection'),
        backgroundColor: HaccpPalette.background,
        foregroundColor: HaccpPalette.graphite,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une tâche'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: _loading
              ? const HaccpSkeleton()
              : _error != null
                  ? HaccpErrorState(
                      message: haccpFriendlyError(
                        _error!,
                        'Impossible de charger le plan de nettoyage',
                      ),
                      onRetry: _load,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: tasks.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: AppSpacing.xl),
                                HaccpEmptyState(
                                  icon: Icons.cleaning_services_outlined,
                                  title: 'Aucune tâche de nettoyage',
                                  message:
                                      'Ajoutez une première tâche pour construire le plan.',
                                ),
                              ],
                            )
                          : _buildList(tasks),
                    ),
        ),
      ),
    );
  }

  Widget _buildList(List<HaccpCleaningTask> tasks) {
    final byZone = <String, List<HaccpCleaningTask>>{};
    for (final t in tasks) {
      byZone.putIfAbsent(t.zone, () => []).add(t);
    }
    final activeCount = tasks.where((t) => t.isActive).length;
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
          title: 'Plan de nettoyage',
          subtitle: '$activeCount tâche(s) active(s) sur ${tasks.length}',
          icon: Icons.cleaning_services_outlined,
        ),
        for (final entry in byZone.entries) ...[
          const SizedBox(height: AppSpacing.md),
          HaccpSection(
            title: entry.key,
            subtitle: '${entry.value.length} tâche(s)',
            icon: Icons.place_outlined,
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: HaccpPalette.border),
                  _CleaningRow(
                    task: entry.value[i],
                    frequency: _frequencyLabel(entry.value[i].frequency),
                    session: _sessionTypeLabel(entry.value[i].sessionType),
                    onTap: () => _openForm(existing: entry.value[i]),
                    onToggle: () => _toggleActive(entry.value[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CleaningRow extends StatelessWidget {
  const _CleaningRow({
    required this.task,
    required this.frequency,
    required this.session,
    required this.onTap,
    required this.onToggle,
  });

  final HaccpCleaningTask task;
  final String frequency;
  final String session;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final muted = !task.isActive;
    final product = task.productUsed;
    final details = [
      frequency,
      session,
      if (product != null && product.isNotEmpty) product,
    ].join(' • ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.name,
                      style: TextStyle(
                        color: muted
                            ? HaccpPalette.graphiteSoft
                            : HaccpPalette.graphite,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        decoration: muted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: const TextStyle(
                        color: HaccpPalette.graphiteSoft,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (muted)
                const Padding(
                  padding: EdgeInsets.only(right: AppSpacing.xs),
                  child: HaccpStatusBadge(
                    label: 'Inactive',
                    tone: HaccpTone.neutral,
                    compact: true,
                  ),
                ),
              Switch(value: task.isActive, onChanged: (_) => onToggle()),
            ],
          ),
        ),
      ),
    );
  }
}

class _CleaningTaskFormDialog extends StatefulWidget {
  const _CleaningTaskFormDialog({this.existing});

  final HaccpCleaningTask? existing;

  @override
  State<_CleaningTaskFormDialog> createState() =>
      _CleaningTaskFormDialogState();
}

class _CleaningTaskFormDialogState extends State<_CleaningTaskFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _zoneController;
  late final TextEditingController _productController;
  late String _frequency;
  late String _sessionType;
  late String _requiredRole;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _nameController = TextEditingController(text: t?.name ?? '');
    _zoneController = TextEditingController(text: t?.zone ?? '');
    _productController = TextEditingController(text: t?.productUsed ?? '');
    _frequency = t?.frequency ?? 'daily';
    _sessionType = t?.sessionType ?? 'both';
    _requiredRole = t?.requiredRole ?? 'staff';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _zoneController.dispose();
    _productController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Nouvelle tâche ND' : 'Modifier la tâche',
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
              TextFormField(
                controller: _zoneController,
                decoration: const InputDecoration(
                  labelText: 'Zone *',
                  hintText: 'Ex: Cuisine, Sanitaires, Plan de travail',
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Champ obligatoire' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                decoration: const InputDecoration(labelText: 'Fréquence'),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('Quotidien')),
                  DropdownMenuItem(
                    value: 'weekly',
                    child: Text('Hebdomadaire'),
                  ),
                  DropdownMenuItem(value: 'monthly', child: Text('Mensuel')),
                  DropdownMenuItem(
                    value: 'per_service',
                    child: Text('Par service'),
                  ),
                ],
                onChanged: (v) => setState(() => _frequency = v!),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _sessionType,
                decoration:
                    const InputDecoration(labelText: 'Session concernée'),
                items: const [
                  DropdownMenuItem(
                    value: 'both',
                    child: Text('Ouverture + Fermeture'),
                  ),
                  DropdownMenuItem(value: 'opening', child: Text('Ouverture')),
                  DropdownMenuItem(value: 'closing', child: Text('Fermeture')),
                ],
                onChanged: (v) => setState(() => _sessionType = v!),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _productController,
                decoration: const InputDecoration(
                  labelText: 'Produit utilisé (optionnel)',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _requiredRole,
                decoration: const InputDecoration(
                  labelText: 'Rôle requis pour valider',
                ),
                items: const [
                  DropdownMenuItem(value: 'staff', child: Text('Staff')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (v) => setState(() => _requiredRole = v!),
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
              'zone': _zoneController.text.trim(),
              'frequency': _frequency,
              'session_type': _sessionType,
              'product_used': _productController.text.trim().isNotEmpty
                  ? _productController.text.trim()
                  : null,
              'required_role': _requiredRole,
            });
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
