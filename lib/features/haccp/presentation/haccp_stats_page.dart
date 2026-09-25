/// Page de statistiques HACCP — scorecard sur période.
///
/// Vue secondaire : affiche uniquement les indicateurs fournis par l'API
/// (score global, sessions, contrôles, non-conformités).
///
/// Accessible via le menu `⋮` dans [HaccpCheckPage] → `/haccp/stats`.
library haccp_stats_page;

import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_ui.dart';
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

  void _setLastN(int days) {
    final now = DateTime.now();
    setState(() {
      _toDate = DateTime(now.year, now.month, now.day);
      _fromDate = _toDate.subtract(Duration(days: days - 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final period = (from: _iso(_fromDate), to: _iso(_toDate));
    final statsAsync = ref.watch(haccpStatsProvider(period));
    final days = _toDate.difference(_fromDate).inDays + 1;

    return Scaffold(
      backgroundColor: HaccpPalette.background,
      appBar: AppBar(
        title: const Text('Scorecard HACCP'),
        backgroundColor: HaccpPalette.background,
        foregroundColor: HaccpPalette.graphite,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_outlined),
            tooltip: 'Changer la période',
            onPressed: _pickRange,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _PeriodBar(
                label: '${_display(_fromDate)} → ${_display(_toDate)}',
                days: days,
                onPick: _pickRange,
                on7: () => _setLastN(7),
                on30: () => _setLastN(30),
              ),
              const SizedBox(height: AppSpacing.md),
              statsAsync.when(
                loading: () => const SizedBox(
                  height: 420,
                  child: HaccpSkeleton(),
                ),
                error: (e, _) => SizedBox(
                  height: 320,
                  child: HaccpErrorState(
                    message: haccpFriendlyError(
                      e,
                      'Impossible de charger les statistiques',
                    ),
                    onRetry: () => ref.invalidate(haccpStatsProvider(period)),
                  ),
                ),
                data: (stats) => _StatsBody(stats: stats),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Barre de période ─────────────────────────────────────────────────────────

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.label,
    required this.days,
    required this.onPick,
    required this.on7,
    required this.on30,
  });

  final String label;
  final int days;
  final VoidCallback onPick;
  final VoidCallback on7;
  final VoidCallback on30;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: HaccpPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HaccpPalette.border),
      ),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: 10,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: HaccpPalette.graphiteSoft,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '$label  ($days j)',
                    style: const TextStyle(
                      color: HaccpPalette.graphite,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ActionChip(label: const Text('7 j'), onPressed: on7),
          ActionChip(label: const Text('30 j'), onPressed: on30),
        ],
      ),
    );
  }
}

// ─── Corps principal ──────────────────────────────────────────────────────────

HaccpTone _toneForRate(double rate) {
  if (rate >= 90) return HaccpTone.ok;
  if (rate >= 70) return HaccpTone.warning;
  return HaccpTone.danger;
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.stats});

  final HaccpStatsData stats;

  @override
  Widget build(BuildContext context) {
    final s = stats.sessions;
    final sessionsDone = s.openingCompleted + s.closingCompleted;
    final sessionsTotal = s.openingTotal + s.closingTotal;
    final controlsDone = stats.temperature.total +
        stats.dlc.total +
        stats.cleaning.total +
        stats.reception.total;
    final scoreTone = stats.overallScore >= 80
        ? HaccpTone.ok
        : stats.overallScore >= 60
            ? HaccpTone.warning
            : HaccpTone.danger;
    final ncOpen = stats.nonConformities.open;

    final kpis = [
      _Kpi(
        label: 'Taux de conformité',
        value: '${stats.overallScore.toStringAsFixed(0)}%',
        tone: scoreTone,
      ),
      _Kpi(
        label: 'Sessions complètes',
        value: '$sessionsDone / $sessionsTotal',
        tone: HaccpTone.neutral,
      ),
      _Kpi(
        label: 'Contrôles réalisés',
        value: '$controlsDone',
        tone: HaccpTone.neutral,
      ),
      _Kpi(
        label: 'NC ouvertes',
        value: '$ncOpen',
        tone: ncOpen > 0 ? HaccpTone.danger : HaccpTone.ok,
      ),
    ];

    final rows = <_RateRow>[
      _RateRow(
        icon: Icons.thermostat_outlined,
        label: 'Températures',
        detail:
            '${stats.temperature.compliant}/${stats.temperature.total} relevés conformes',
        rate: stats.temperature.complianceRate,
      ),
      _RateRow(
        icon: Icons.calendar_today_outlined,
        label: 'Vérifications DLC',
        detail: '${stats.dlc.compliant}/${stats.dlc.total} conformes',
        rate: stats.dlc.complianceRate,
      ),
      _RateRow(
        icon: Icons.cleaning_services_outlined,
        label: 'Nettoyage',
        detail: '${stats.cleaning.compliant}/${stats.cleaning.total} réalisées',
        rate: stats.cleaning.complianceRate,
      ),
      _RateRow(
        icon: Icons.local_shipping_outlined,
        label: 'Réceptions',
        detail:
            '${stats.reception.compliant}/${stats.reception.total} acceptées',
        rate: stats.reception.complianceRate,
      ),
      _RateRow(
        icon: Icons.ac_unit_outlined,
        label: 'Refroidissement',
        detail:
            '${stats.cooling.compliant}/${stats.cooling.compliant + stats.cooling.nonCompliant} conformes'
            '${stats.cooling.inProgress > 0 ? ' • ${stats.cooling.inProgress} en cours' : ''}',
        rate: stats.cooling.complianceRate,
        applicable: stats.cooling.compliant + stats.cooling.nonCompliant > 0,
      ),
    ];

    final nc = stats.nonConformities;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 4 : 2;
            final width =
                (constraints.maxWidth - (columns - 1) * AppSpacing.sm) /
                    columns;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final k in kpis) SizedBox(width: width, child: k),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        HaccpSection(
          title: 'Conformité par catégorie',
          icon: Icons.fact_check_outlined,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: HaccpPalette.border),
                rows[i],
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        HaccpSection(
          title: 'Non-conformités',
          icon: Icons.report_problem_outlined,
          tone: ncOpen > 0 ? HaccpTone.danger : HaccpTone.neutral,
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              HaccpStatusBadge(
                label: '${nc.open} ouverte(s)',
                tone: nc.open > 0 ? HaccpTone.danger : HaccpTone.neutral,
              ),
              HaccpStatusBadge(
                label: '${nc.inProgress} en cours',
                tone: nc.inProgress > 0 ? HaccpTone.warning : HaccpTone.neutral,
              ),
              HaccpStatusBadge(
                label: '${nc.closed} clôturée(s)',
                tone: nc.closed > 0 ? HaccpTone.ok : HaccpTone.neutral,
              ),
              if (nc.total > 0)
                HaccpStatusBadge(
                  label: 'Résolution ${nc.resolutionRate.toStringAsFixed(0)}%',
                  tone: _toneForRate(nc.resolutionRate),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final HaccpTone tone;

  @override
  Widget build(BuildContext context) {
    final style = haccpToneStyle(tone);
    final accent =
        tone == HaccpTone.neutral ? HaccpPalette.graphite : style.foreground;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: HaccpPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HaccpPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: accent,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: HaccpPalette.graphiteSoft,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _RateRow extends StatelessWidget {
  const _RateRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.rate,
    this.applicable = true,
  });

  final IconData icon;
  final String label;
  final String detail;
  final double rate;
  final bool applicable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: HaccpPalette.graphiteSoft),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: HaccpPalette.graphite,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    color: HaccpPalette.graphiteSoft,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          HaccpStatusBadge(
            label: applicable ? '${rate.toStringAsFixed(0)}%' : '—',
            tone: applicable ? _toneForRate(rate) : HaccpTone.neutral,
            compact: true,
          ),
        ],
      ),
    );
  }
}
