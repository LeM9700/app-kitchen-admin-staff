import 'dart:io';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Page d'export HACCP — PDF et CSV.
///
/// Permet de générer et partager les rapports du dossier PMS :
///   - PDF complet (rapport multi-sections, compatible inspection DDPP)
///   - CSV par type de données (températures, DLC, NC, réception, refroidissement)
///
/// Les fichiers sont téléchargés via l'API (avec Bearer token),
/// sauvegardés dans le répertoire temporaire, puis partagés via share_plus.
class HaccpExportPage extends ConsumerStatefulWidget {
  const HaccpExportPage({super.key});

  @override
  ConsumerState<HaccpExportPage> createState() => _HaccpExportPageState();
}

class _HaccpExportPageState extends ConsumerState<HaccpExportPage> {
  // Période sélectionnée (défaut : 7 derniers jours)
  late DateTime _fromDate;
  late DateTime _toDate;

  // État des exports
  bool _exportingPdf = false;
  bool _exportingCsv = false;

  // Sélection UI (n'affecte que le choix de l'utilisateur, pas les requêtes)
  _ExportFormat _format = _ExportFormat.pdf;
  String _selectedType = 'all';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _toDate = DateTime(now.year, now.month, now.day);
    _fromDate = _toDate.subtract(const Duration(days: 6));
  }

  // ── Helpers dates ────────────────────────────────────────────────────────

  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      helpText: 'Sélectionner la période d\'export',
      saveText: 'Confirmer',
    );
    if (range != null) {
      setState(() {
        _fromDate = range.start;
        _toDate = range.end;
      });
    }
  }

  // ── Raccourcis de période ────────────────────────────────────────────────

  void _setLastN(int days) {
    final now = DateTime.now();
    setState(() {
      _toDate = DateTime(now.year, now.month, now.day);
      _fromDate = _toDate.subtract(Duration(days: days - 1));
    });
  }

  void _setCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _fromDate = DateTime(now.year, now.month, 1);
      _toDate = DateTime(now.year, now.month, now.day);
    });
  }

  void _setLastMonth() {
    final now = DateTime.now();
    final lastMonth = now.month == 1
        ? DateTime(now.year - 1, 12, 1)
        : DateTime(now.year, now.month - 1, 1);
    final lastDay = DateTime(lastMonth.year, lastMonth.month + 1, 0);
    setState(() {
      _fromDate = lastMonth;
      _toDate = lastDay;
    });
  }

  // ── Téléchargement et partage ────────────────────────────────────────────

  Future<void> _exportPdf() async {
    setState(() => _exportingPdf = true);
    try {
      final api = ref.read(apiClientProvider);
      final from = _isoDate(_fromDate);
      final to = _isoDate(_toDate);

      final response = await api.get(
        ApiEndpoints.haccpExportPdf,
        queryParameters: {'from': from, 'to': to},
        responseType: ResponseType.bytes,
      );

      final bytes = response.data as List<int>?;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('PDF vide reçu du serveur');
      }

      final tmpDir = await getTemporaryDirectory();
      final file = File('${tmpDir.path}/haccp_${from}_$to.pdf');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Rapport HACCP $_fromDate → $to',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              haccpFriendlyError(e, 'Export PDF impossible'),
            ),
            backgroundColor: haccpToneStyle(HaccpTone.danger).foreground,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _exportCsv(String type) async {
    setState(() {
      _exportingCsv = true;
    });
    try {
      final api = ref.read(apiClientProvider);
      final from = _isoDate(_fromDate);
      final to = _isoDate(_toDate);

      final response = await api.get(
        ApiEndpoints.haccpExportCsv,
        queryParameters: {'from': from, 'to': to, 'data_type': type},
        responseType: ResponseType.bytes,
      );

      final bytes = response.data as List<int>?;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('CSV vide reçu du serveur');
      }

      final tmpDir = await getTemporaryDirectory();
      final file = File('${tmpDir.path}/haccp_${from}_${to}_$type.csv');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'HACCP — $type — $from → $to',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              haccpFriendlyError(e, 'Export CSV impossible'),
            ),
            backgroundColor: haccpToneStyle(HaccpTone.danger).foreground,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _exportingCsv = false;
        });
      }
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isExporting = _exportingPdf || _exportingCsv;
    final days = _toDate.difference(_fromDate).inDays + 1;
    final selected = _csvOptions.firstWhere((o) => o.type == _selectedType);

    return Scaffold(
      backgroundColor: HaccpPalette.background,
      appBar: AppBar(
        title: const Text('Export HACCP / PMS'),
        backgroundColor: HaccpPalette.background,
        foregroundColor: HaccpPalette.graphite,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const HaccpInfoBanner(
                icon: Icons.info_outline,
                title: 'Dossier PMS numérique',
                message:
                    'Règlement CE 852/2004 + arrêté 12/02/2024. À conserver 5 ans. '
                    'Présentable lors d\'une inspection DDPP/DGAL.',
                tone: HaccpTone.info,
              ),
              const SizedBox(height: AppSpacing.md),

              // Période
              HaccpSection(
                title: 'Période',
                icon: Icons.date_range_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: isExporting ? null : _pickDateRange,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: HaccpPalette.surfaceWarm,
                          border: Border.all(color: HaccpPalette.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.date_range,
                              color: HaccpPalette.graphite,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_displayDate(_fromDate)} → ${_displayDate(_toDate)}',
                                    style: const TextStyle(
                                      color: HaccpPalette.graphite,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    '$days jour(s)',
                                    style: const TextStyle(
                                      color: HaccpPalette.graphiteSoft,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: HaccpPalette.graphiteSoft,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        ActionChip(
                          label: const Text('7 jours'),
                          onPressed: isExporting ? null : () => _setLastN(7),
                        ),
                        ActionChip(
                          label: const Text('30 jours'),
                          onPressed: isExporting ? null : () => _setLastN(30),
                        ),
                        ActionChip(
                          label: const Text('Ce mois'),
                          onPressed: isExporting ? null : _setCurrentMonth,
                        ),
                        ActionChip(
                          label: const Text('Mois précédent'),
                          onPressed: isExporting ? null : _setLastMonth,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Format
              HaccpSection(
                title: 'Format',
                icon: Icons.description_outlined,
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_ExportFormat>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: _ExportFormat.pdf,
                        icon: Icon(Icons.picture_as_pdf_outlined),
                        label: Text('PDF'),
                      ),
                      ButtonSegment(
                        value: _ExportFormat.csv,
                        icon: Icon(Icons.table_chart_outlined),
                        label: Text('CSV'),
                      ),
                    ],
                    selected: {_format},
                    onSelectionChanged: isExporting
                        ? null
                        : (v) => setState(() => _format = v.first),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Type de données
              HaccpSection(
                title: 'Type de données',
                subtitle: _format == _ExportFormat.pdf
                    ? 'Le PDF regroupe toutes les sections du dossier.'
                    : selected.subtitle,
                icon: Icons.category_outlined,
                child: _format == _ExportFormat.pdf
                    ? const HaccpStatusBadge(
                        label: 'Rapport complet',
                        tone: HaccpTone.neutral,
                      )
                    : Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final opt in _csvOptions)
                            ChoiceChip(
                              avatar: Icon(opt.icon, size: 18),
                              label: Text(opt.label),
                              selected: _selectedType == opt.type,
                              onSelected: isExporting
                                  ? null
                                  : (_) =>
                                      setState(() => _selectedType = opt.type),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),

              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: isExporting
                      ? null
                      : () => _format == _ExportFormat.pdf
                          ? _exportPdf()
                          : _exportCsv(_selectedType),
                  icon: isExporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.file_download_outlined),
                  label: Text(
                    isExporting ? 'GÉNÉRATION EN COURS…' : 'GÉNÉRER',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: HaccpPalette.graphite,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ExportFormat { pdf, csv }

// ─── Options CSV ──────────────────────────────────────────────────────────────

class _CsvOption {
  const _CsvOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.type,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String type;
}

const _csvOptions = [
  _CsvOption(
    icon: Icons.download_outlined,
    label: 'Toutes les données',
    subtitle: 'Un seul fichier avec toutes les sections HACCP',
    type: 'all',
  ),
  _CsvOption(
    icon: Icons.thermostat_outlined,
    label: 'Températures',
    subtitle: 'Relevés de température par équipement',
    type: 'temperatures',
  ),
  _CsvOption(
    icon: Icons.calendar_today_outlined,
    label: 'Vérifications DLC',
    subtitle: 'DLC emballage, conservation, utilisation',
    type: 'dlc',
  ),
  _CsvOption(
    icon: Icons.report_problem_outlined,
    label: 'Non-conformités',
    subtitle: 'Écarts + actions correctives + statuts',
    type: 'nc',
  ),
  _CsvOption(
    icon: Icons.local_shipping_outlined,
    label: 'Contrôles réception',
    subtitle: 'Réceptions fournisseurs avec conformité',
    type: 'reception',
  ),
  _CsvOption(
    icon: Icons.ac_unit_outlined,
    label: 'Refroidissement rapide',
    subtitle: 'Suivi T° initiale → finale',
    type: 'cooling',
  ),
];
