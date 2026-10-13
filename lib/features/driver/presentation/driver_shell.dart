import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/driver/application/location_sharing.dart';
import 'package:app_admin_staff/features/driver/application/location_sharing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Les trois seuls ecrans d'un livreur : ses livraisons, son recapitulatif, son pointage.
/// Aucun autre menu : le livreur ne se disperse pas (et l'API refuse de toute facon
/// tout le reste a ce role).
const driverDestinations = <({String path, String label, IconData icon})>[
  (path: '/driver', label: 'Livraisons', icon: Icons.delivery_dining_outlined),
  (path: '/driver/recap', label: 'Recap', icon: Icons.receipt_long_outlined),
  (path: '/driver/clock', label: 'Pointage', icon: Icons.punch_clock_outlined),
];

int driverDestinationIndex(String location) {
  var best = 0;
  for (var i = 0; i < driverDestinations.length; i++) {
    final path = driverDestinations[i].path;
    if (location == path || location.startsWith('$path/')) {
      if (path.length >= driverDestinations[best].path.length) best = i;
    }
  }
  return best;
}

class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  ConsumerState<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<DriverShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Retour au premier plan : etat des livraisons et du consentement a jour, autorisation GPS
    // reverifiee (le livreur a pu la retirer pendant que l'application etait en arriere-plan) et
    // envoi immediat de ce qui attendait.
    ref
      ..invalidate(driverDeliveriesProvider)
      ..invalidate(driverMeProvider);
    final sharer = ref.read(driverLocationSharerProvider.notifier);
    sharer.recheckPermission().then((_) => sharer.flush());
  }

  @override
  Widget build(BuildContext context) {
    // Le partage de position vit avec la coque : meme onglet change, meme application en
    // arriere-plan. Il est coupe des que la coque disparait (deconnexion).
    ref.watch(driverLocationControllerProvider);
    final location = widget.location;
    final child = widget.child;
    final index = driverDestinationIndex(location);
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    return Scaffold(
      appBar: AppBar(
        title: Text(driverDestinations[index].label),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Text(
                  user.email,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          IconButton(
            key: const ValueKey('driver-logout'),
            tooltip: 'Se deconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) =>
            context.go(driverDestinations[value].path),
        destinations: [
          for (final destination in driverDestinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}
