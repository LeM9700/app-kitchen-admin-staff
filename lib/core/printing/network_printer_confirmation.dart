import 'package:flutter/widgets.dart';

/// Ties a network printer's "target confirmed" flag to the exact host/port
/// it was confirmed for.
///
/// A stored `confirmed: true` only means something if it still describes the
/// address someone actually looked at. Without this, an operator could
/// confirm `192.168.1.50`, later retype the host to a different address, and
/// the app would keep treating the new (unreviewed) address as confirmed.
/// This tracker clears [confirmed] as soon as either [hostController] or
/// [portController] is edited, and only [confirmed]'s setter (wired to the
/// explicit confirmation checkbox) can set it back to `true`.
class NetworkPrinterConfirmationTracker {
  NetworkPrinterConfirmationTracker({
    required this.hostController,
    required this.portController,
    bool initiallyConfirmed = false,
    this.onChanged,
  }) : _confirmed = initiallyConfirmed {
    hostController.addListener(_handleFieldEdited);
    portController.addListener(_handleFieldEdited);
  }

  final TextEditingController hostController;
  final TextEditingController portController;

  /// Called when [confirmed] flips to `false` because of a field edit. Not
  /// called when [confirmed] is set explicitly through its setter.
  final VoidCallback? onChanged;

  bool _confirmed;

  /// Whether the current host/port pair has been explicitly confirmed.
  /// Defaults to `false` for any configuration that never recorded an
  /// explicit confirmation (legacy data included).
  bool get confirmed => _confirmed;

  set confirmed(bool value) => _confirmed = value;

  void _handleFieldEdited() {
    if (_confirmed) {
      _confirmed = false;
      onChanged?.call();
    }
  }

  void dispose() {
    hostController.removeListener(_handleFieldEdited);
    portController.removeListener(_handleFieldEdited);
  }
}
