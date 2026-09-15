import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:app_admin_staff/features/haccp/presentation/dlc_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Gestion des vérifications DLC depuis l'onglet Stock -- indépendante d'une
/// session HACCP ouverture/fermeture (CRUD complet : créer, modifier,
/// supprimer). Les entrées créées ici n'ont pas de session rattachée
/// (`POST /haccp/dlc`), contrairement à celles loguées pendant un check.
class StockDlcPage extends ConsumerStatefulWidget {
  const StockDlcPage({super.key});

  @override
  ConsumerState<StockDlcPage> createState() => _StockDlcPageState();
}

class _StockDlcPageState extends ConsumerState<StockDlcPage> {
  List<HaccpDlcCheck>? _checks;
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
      final checks = await ref.read(haccpRepositoryProvider).listAllDlcChecks();
      if (mounted) setState(() => _checks = checks);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const DlcFormDialog(),
    );
    if (result == null) return;
    try {
      await ref.read(haccpRepositoryProvider).createStandaloneDlcCheck(result);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _edit(HaccpDlcCheck check) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => DlcFormDialog(existing: check),
    );
    if (result == null) return;
    try {
      await ref.read(haccpRepositoryProvider).updateDlcCheck(check.id, result);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _delete(HaccpDlcCheck check) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer cette vérification DLC ?'),
        content: Text(
          '${check.ingredientName} — ${_formatDate(check.dlcDate)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(haccpRepositoryProvider).deleteDlcCheck(check.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vérifications DLC')),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Erreur : $_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: (_checks ?? const []).isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Text(
                                'Aucune vérification DLC. Appuyez sur + pour '
                                'en créer une.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _checks!.length,
                          itemBuilder: (context, index) {
                            final c = _checks![index];
                            return Dismissible(
                              key: ValueKey(c.id),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) async {
                                await _delete(c);
                                return false;
                              },
                              background: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                ),
                                child: const Icon(Icons.delete,
                                    color: Colors.white),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  c.isCompliant
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color:
                                      c.isCompliant ? Colors.green : Colors.red,
                                ),
                                title: Text(c.ingredientName),
                                subtitle: Text(
                                  '${c.levelLabel} • ${_formatDate(c.dlcDate)}'
                                  '${c.location != null ? ' • ${c.location}' : ''}'
                                  '${c.sessionId == null ? ' • Hors session' : ''}',
                                ),
                                onTap: () => _edit(c),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(c),
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
