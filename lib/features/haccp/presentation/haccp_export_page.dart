import 'dart:io';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
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
  String? _csvType;

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
      if (bytes == null || bytes.isEmpty)
        throw Exception('PDF vide reçu du serveur');

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
              content: Text('Erreur export PDF : $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _exportCsv(String type) async {
    setState(() {
      _exportingCsv = true;
      _csvType = type;
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
      if (bytes == null || bytes.isEmpty)
        throw Exception('CSV vide reçu du serveur');

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
              content: Text('Erreur export CSV : $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _exportingCsv = false;
          _csvType = null;
        });
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isExporting = _exportingPdf || _exportingCsv;

    return Scaffold(
      appBar: AppBar(title: const Text('Export HACCP / PMS')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Infos légales
          _InfoBanner(
            icon: Icons.info_outline,
            text:
                'Ces documents constituent le dossier PMS numérique (Règlement CE 852/2004 + arrêté 12/02/2024). '
                'À conserver 5 ans. Présentable lors d\'une inspection DDPP/DGAL.',
            color: Colors.blue,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Sélecteur de période
          Text('Période', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range, color: Colors.blue),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_displayDate(_fromDate)} → ${_displayDate(_toDate)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        Text(
                          '${_toDate.difference(_fromDate).inDays + 1} jour(s)',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Raccourcis période
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              ActionChip(
                  label: const Text('7 jours'), onPressed: () => _setLastN(7)),
              ActionChip(
                  label: const Text('30 jours'),
                  onPressed: () => _setLastN(30)),
              ActionChip(
                  label: const Text('Ce mois'), onPressed: _setCurrentMonth),
              ActionChip(
                  label: const Text('Mois précédent'),
                  onPressed: _setLastMonth),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // Export PDF
          Text('Rapport complet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'PDF multi-sections : sessions, températures, DLC, nettoyage, NC, '
            'réceptions, refroidissements, formations.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isExporting ? null : _exportPdf,
              icon: _exportingPdf
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf),
              label: Text(
                  _exportingPdf ? 'Génération en cours…' : 'Exporter en PDF'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red[700],
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Export CSV
          Text('Exports CSV', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Fichiers CSV compatibles Excel (UTF-8 BOM). Utile pour analyser '
            'les données ou les importer dans un tableur.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.sm),

          ..._csvOptions.map((opt) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _CsvExportTile(
                  icon: opt.icon,
                  label: opt.label,
                  subtitle: opt.subtitle,
                  type: opt.type,
                  loading: _exportingCsv && _csvType == opt.type,
                  disabled: isExporting,
                  onTap: () => _exportCsv(opt.type),
                ),
              )),
        ],
      ),
    );
  }
}

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

// ─── Widgets utilitaires ──────────────────────────────────────────────────────

class _CsvExportTile extends StatelessWidget {
  const _CsvExportTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.type,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String type;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.green),
                )
              : Icon(icon, color: Colors.green[700], size: 20),
        ),
        title: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: disabled
            ? const SizedBox.shrink()
            : const Icon(Icons.share_outlined, size: 18, color: Colors.grey),
        onTap: disabled ? null : onTap,
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(
      {required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 12, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
