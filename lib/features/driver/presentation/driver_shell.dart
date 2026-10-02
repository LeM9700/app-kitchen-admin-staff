import 'package:app_admin_staff/core/auth/session_controller.dart';
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

class DriverShell extends ConsumerWidget {
  const DriverShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            onPressed: () => ref.read(sessionControllerProvider.notifier).logout(),
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
