import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
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
      final tasks = await ref.read(haccpRepositoryProvider).listCleaningTasks();
      if (mounted) setState(() => _tasks = tasks);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
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
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
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
        return 'Ouverture';
      case 'closing':
        return 'Fermeture';
      default:
        return 'Ouverture + Fermeture';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan de nettoyage & désinfection')),
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
                  child: (_tasks ?? const []).isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Text(
                                'Aucune tâche de nettoyage. Appuyez sur + pour '
                                'en ajouter une.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _tasks!.length,
                          itemBuilder: (context, index) {
                            final t = _tasks![index];
                            return ListTile(
                              leading: Icon(
                                Icons.cleaning_services_outlined,
                                color: t.isActive ? null : Colors.grey,
                              ),
                              title: Text(
                                t.name,
                                style: TextStyle(
                                  color: t.isActive ? null : Colors.grey,
                                  decoration: t.isActive
                                      ? null
                                      : TextDecoration.lineThrough,
                                ),
                              ),
                              subtitle: Text(
                                '${t.zone} • ${_frequencyLabel(t.frequency)} • '
                                '${_sessionTypeLabel(t.sessionType)}'
                                '${t.productUsed != null ? ' • ${t.productUsed}' : ''}',
                              ),
                              onTap: () => _openForm(existing: t),
                              trailing: Switch(
                                value: t.isActive,
                                onChanged: (_) => _toggleActive(t),
                              ),
                            );
                          },
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
