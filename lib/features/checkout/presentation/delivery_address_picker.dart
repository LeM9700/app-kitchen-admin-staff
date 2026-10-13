import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Adresse de livraison d'une commande saisie au comptoir.
///
/// Le staff cherche l'adresse (suggestions via le geocodage serveur) : la zone, les frais et
/// le delai se calculent tout de suite avec le panier en cours. Si la recherche est
/// indisponible, la zone se choisit a la main (le serveur accepte alors une zone sans
/// coordonnees pour une commande manuelle).
class DeliveryAddressPicker extends ConsumerStatefulWidget {
  const DeliveryAddressPicker({
    required this.controller,
    required this.zoneId,
    required this.onZoneChanged,
    required this.onPointChanged,
    required this.subtotal,
    required this.onChanged,
    this.establishmentId,
    this.near,
    super.key,
  });

  final TextEditingController controller;
  final int? zoneId;
  final ValueChanged<int?> onZoneChanged;

  /// Point GPS retenu (ou `null` si l'adresse a ete modifiee a la main / zone choisie a la main).
  final ValueChanged<LatLng?> onPointChanged;
  final double subtotal;
  final VoidCallback onChanged;
  final int? establishmentId;

  /// Position du restaurant, pour favoriser les adresses proches dans les suggestions.
  final LatLng? near;

  @override
  ConsumerState<DeliveryAddressPicker> createState() =>
      _DeliveryAddressPickerState();
}

class _DeliveryAddressPickerState extends ConsumerState<DeliveryAddressPicker> {
  List<AddressSuggestion> _suggestions = const [];
  bool _busy = false;
  String? _problem;
  DeliveryCheckResult? _result;
  bool _outside = false;

  Future<void> _search() async {
    final text = widget.controller.text.trim();
    if (text.length < 3) {
      setState(() => _problem = 'Saisissez au moins 3 caracteres');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
      _result = null;
      _outside = false;
    });
    try {
      final results = await ref
          .read(deliveryRepositoryProvider)
          .geocode(text, near: widget.near);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        if (results.isEmpty) {
          _problem =
              'Aucune adresse trouvee. Choisissez la zone a la main ci-dessous.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _suggestions = const [];
        _problem = error is AppException && error.statusCode == 503
            ? 'Recherche d\'adresse indisponible : choisissez la zone a la main ci-dessous.'
            : (error is AppException ? error.message : 'Recherche impossible');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(AddressSuggestion suggestion) async {
    widget.controller.text = suggestion.label;
    widget.onPointChanged(suggestion.point);
    setState(() {
      _suggestions = const [];
      _busy = true;
      _problem = null;
    });
    try {
      final result = await ref
          .read(deliveryRepositoryProvider)
          .checkAddress(
            lat: suggestion.point.latitude,
            lng: suggestion.point.longitude,
            address: suggestion.label,
            subtotal: widget.subtotal,
            establishmentId: widget.establishmentId,
          );
      if (!mounted) return;
      widget.onZoneChanged(result.zoneId);
      setState(() {
        _result = result;
        _outside = false;
      });
    } catch (error) {
      if (!mounted) return;
      widget.onZoneChanged(null);
      widget.onPointChanged(null);
      setState(() {
        _result = null;
        if (error is AppException &&
            error.code == 'DELIVERY_ZONE_UNREACHABLE') {
          _outside = true;
        } else {
          _problem = error is AppException
              ? error.message
              : 'Verification impossible';
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onTyped(String _) {
    // L'adresse ne correspond plus au point retenu.
    widget.onPointChanged(null);
    setState(() {
      _result = null;
      _outside = false;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('checkout-delivery-address'),
          controller: widget.controller,
          onChanged: _onTyped,
          onSubmitted: (_) => _search(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Adresse de livraison',
            prefixIcon: const Icon(Icons.location_on_outlined),
            suffixIcon: IconButton(
              key: const ValueKey('checkout-address-search'),
              tooltip: 'Rechercher l\'adresse',
              icon: const Icon(Icons.search),
              onPressed: _busy ? null : _search,
            ),
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xs),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        for (final suggestion in _suggestions)
          ListTile(
            key: ValueKey('checkout-suggestion-${suggestion.label}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined, size: 20),
            title: Text(suggestion.label),
            onTap: () => _choose(suggestion),
          ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              _problem!,
              key: const ValueKey('checkout-address-problem'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        if (_outside)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Adresse hors zone de livraison.',
              key: const ValueKey('checkout-address-outside'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (result != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              [
                'Zone ${result.name}',
                if (result.freeDelivery)
                  'livraison offerte'
                else
                  'frais ${formatMoney(result.fee)}',
                '${result.estimatedMinutes} min',
                if (result.minOrderMet == false)
                  'minimum ${formatMoney(result.minOrderAmount)} non atteint',
              ].join(' · '),
              key: const ValueKey('checkout-address-result'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: result.minOrderMet == false
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
