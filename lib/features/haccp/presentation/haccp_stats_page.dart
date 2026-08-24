/// Page de statistiques HACCP — scorecard hebdomadaire.
///
/// Affiche le score global de conformité sur une période choisie,
/// ainsi que les taux par catégorie :
///   - Sessions (ouverture/fermeture complétées)
///   - Températures, DLC, Nettoyage
///   - Non-conformités (open/en cours/clôturées)
///   - Réceptions fournisseurs
///   - Refroidissements rapides
///
/// Accessible via le menu `⋮` dans [HaccpCheckPage] → `/haccp/stats`.
library haccp_stats_page;

import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HaccpStatsPage extends ConsumerStatefulWidget {
  const HaccpStatsPage({super.key});

  @override
  ConsumerState<HaccpStatsPage> createState() => _HaccpStatsPageState();
}

class _HaccpStatsPageState extends ConsumerState<HaccpStatsPage> {
  // Période par défaut : 7 derniers jours
  late DateTime _fromDate;
  late DateTime _toDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _toDate = DateTime(now.year, now.month, now.day);
    _fromDate = _toDate.subtract(const Duration(days: 6));
  }

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _display(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      helpText: 'Période du scorecard',
      saveText: 'Confirmer',
    );
    if (range != null) {
      setState(() {
        _fromDate = range.start;
        _toDate = range.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final period = (from: _iso(_fromDate), to: _iso(_toDate));
    final statsAsync = ref.watch(haccpStatsProvider(period));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scorecard HACCP'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_outlined),
            tooltip: 'Changer la période',
            onPressed: _pickRange,
          ),
        ],
      ),
      body: Column(
        children: [
          // Sélecteur de période compact
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${_display(_fromDate)} → ${_display(_toDate)}  '
                  '(${_toDate.difference(_fromDate).inDays + 1}j)',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const Spacer(),
                // Raccourcis rapides
                TextButton(
                  onPressed: () {
                    final now = DateTime.now();
                    setState(() {
                      _toDate = DateTime(now.year, now.month, now.day);
                      _fromDate = _toDate.subtract(const Duration(days: 6));
                    });
                  },
                  child: const Text('7j', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () {
                    final now = DateTime.now();
                    setState(() {
                      _toDate = DateTime(now.year, now.month, now.day);
                      _fromDate = _toDate.subtract(const Duration(days: 29));
                    });
                  },
                  child: const Text('30j', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),

          Expanded(
            child: statsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: AppSpacing.sm),
                    Text(e.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () =>
                          ref.invalidate(haccpStatsProvider(period)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (stats) => _StatsBody(stats: stats),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Corps principal ──────────────────────────────────────────────────────────

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.stats});

  final HaccpStatsData stats;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // Score global
        _ScoreGauge(score: stats.overallScore),
        const SizedBox(height: AppSpacing.lg),

        // Sessions
        _SectionHeader(
          icon: Icons.assignment_turned_in_outlined,
          label: 'Sessions HACCP',
        ),
        const SizedBox(height: AppSpacing.xs),
        _SessionCard(sessions: stats.sessions),
        const SizedBox(height: AppSpacing.md),

        // Températures
        _SectionHeader(icon: Icons.thermostat_outlined, label: 'Températures'),
        const SizedBox(height: AppSpacing.xs),
        _StatCard(
          section: stats.temperature,
          color: _colorForRate(stats.temperature.complianceRate),
          subtitle:
              '${stats.temperature.compliant}/${stats.temperature.total} relevés conformes',
        ),
        const SizedBox(height: AppSpacing.md),

        // DLC
        _SectionHeader(
            icon: Icons.calendar_today_outlined, label: 'Vérifications DLC'),
        const SizedBox(height: AppSpacing.xs),
        _StatCard(
          section: stats.dlc,
          color: _colorForRate(stats.dlc.complianceRate),
          subtitle:
              '${stats.dlc.compliant}/${stats.dlc.total} vérifications conformes',
        ),
        const SizedBox(height: AppSpacing.md),

        // Nettoyage
        _SectionHeader(
            icon: Icons.cleaning_services_outlined, label: 'Nettoyage'),
        const SizedBox(height: AppSpacing.xs),
        _StatCard(
          section: stats.cleaning,
          color: _colorForRate(stats.cleaning.complianceRate),
          subtitle:
              '${stats.cleaning.compliant}/${stats.cleaning.total} tâches réalisées',
        ),
        const SizedBox(height: AppSpacing.md),

        // Non-conformités
        _SectionHeader(
            icon: Icons.report_problem_outlined, label: 'Non-conformités'),
        const SizedBox(height: AppSpacing.xs),
        _NcCard(nc: stats.nonConformities),
        const SizedBox(height: AppSpacing.md),

        // Réceptions
        _SectionHeader(
            icon: Icons.local_shipping_outlined,
            label: 'Réceptions fournisseurs'),
        const SizedBox(height: AppSpacing.xs),
        _StatCard(
          section: stats.reception,
          color: _colorForRate(stats.reception.complianceRate),
          subtitle:
              '${stats.reception.compliant}/${stats.reception.total} réceptions acceptées',
        ),
        const SizedBox(height: AppSpacing.md),

        // Refroidissement
        _SectionHeader(
            icon: Icons.ac_unit_outlined, label: 'Refroidissement rapide'),
        const SizedBox(height: AppSpacing.xs),
        _CoolingCard(cooling: stats.cooling),
        const SizedBox(height: AppSpacing.xl),

        // Note légale
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 16),
              SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Score basé sur : sessions 20%, températures 25%, DLC 20%, '
                  'nettoyage 15%, NC 10%, réception 5%, refroidissement 5%. '
                  'Objectif DDPP : ≥ 80%.',
                  style: TextStyle(color: Colors.blue, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _colorForRate(double rate) {
    if (rate >= 90) return Colors.green;
    if (rate >= 70) return Colors.orange;
    return Colors.red;
  }
}

// ─── Jauge score global ───────────────────────────────────────────────────────

class _ScoreGauge extends StatelessWidget {
  const _ScoreGauge({required this.score});

  final double score;

  Color get _color {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  String get _label {
    if (score >= 80) return 'Bon niveau';
    if (score >= 60) return 'À améliorer';
    return 'Insuffisant';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            // Cercle de score
            SizedBox(
              width: 88,
              height: 88,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(_color),
                  ),
                  Text(
                    '${score.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Score de conformité',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _label,
                      style: TextStyle(
                        color: _color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    score >= 80
                        ? 'Conforme aux exigences réglementaires.'
                        : 'Des actions correctives sont nécessaires.',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
        ),
      ],
    );
  }
}

// ─── Carte stat générique ──────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.section,
    required this.color,
    required this.subtitle,
  });

  final HaccpStatSection section;
  final Color color;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${section.complianceRate.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Barre de progression verticale
            SizedBox(
              width: 8,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: section.complianceRate / 100,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 56,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Carte sessions ───────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.sessions});

  final HaccpSessionStats sessions;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            _SessionRow(
              icon: Icons.wb_sunny_outlined,
              label: 'Ouverture',
              done: sessions.openingCompleted,
              total: sessions.openingTotal,
            ),
            const Divider(height: 20),
            _SessionRow(
              icon: Icons.nights_stay_outlined,
              label: 'Fermeture',
              done: sessions.closingCompleted,
              total: sessions.closingTotal,
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Taux de complétion',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${sessions.completionRate.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: sessions.completionRate >= 80
                        ? Colors.green
                        : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.icon,
    required this.label,
    required this.done,
    required this.total,
  });

  final IconData icon;
  final String label;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final rate = total == 0 ? 1.0 : done / total;
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Text(
          '$done / $total',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: rate >= 0.8 ? Colors.green : Colors.orange,
          ),
        ),
      ],
    );
  }
}

// ─── Carte NC ─────────────────────────────────────────────────────────────────

class _NcCard extends StatelessWidget {
  const _NcCard({required this.nc});

  final HaccpNcStats nc;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Row(
              children: [
                _NcPill(label: 'Ouvertes', count: nc.open, color: Colors.red),
                const SizedBox(width: AppSpacing.xs),
                _NcPill(
                    label: 'En cours',
                    count: nc.inProgress,
                    color: Colors.orange),
                const SizedBox(width: AppSpacing.xs),
                _NcPill(
                    label: 'Clôturées', count: nc.closed, color: Colors.green),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Taux de résolution',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  nc.total == 0
                      ? 'Aucune NC'
                      : '${nc.resolutionRate.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color:
                        nc.resolutionRate >= 80 ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NcPill extends StatelessWidget {
  const _NcPill(
      {required this.label, required this.count, required this.color});

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Carte cooling ────────────────────────────────────────────────────────────

class _CoolingCard extends StatelessWidget {
  const _CoolingCard({required this.cooling});

  final HaccpCoolingStats cooling;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Row(
              children: [
                _NcPill(
                    label: 'Conformes',
                    count: cooling.compliant,
                    color: Colors.green),
                const SizedBox(width: AppSpacing.xs),
                _NcPill(
                    label: 'NC',
                    count: cooling.nonCompliant,
                    color: Colors.red),
                const SizedBox(width: AppSpacing.xs),
                _NcPill(
                    label: 'En cours',
                    count: cooling.inProgress,
                    color: Colors.blue),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Seuil légal : ≤10°C en 2h',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                Text(
                  cooling.compliant + cooling.nonCompliant == 0
                      ? '—'
                      : '${cooling.complianceRate.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: cooling.complianceRate >= 80
                        ? Colors.green
                        : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
