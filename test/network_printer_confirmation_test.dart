import 'package:app_admin_staff/core/printing/network_printer_confirmation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkPrinterConfirmationTracker', () {
    test('une config historique sans confirmation explicite est refusee',
        () {
      final tracker = NetworkPrinterConfirmationTracker(
        hostController: TextEditingController(text: '192.168.1.50'),
        portController: TextEditingController(text: '9100'),
      );
      expect(tracker.confirmed, isFalse);
      tracker.dispose();
    });

    test('respecte la valeur initialement confirmee', () {
      final tracker = NetworkPrinterConfirmationTracker(
        hostController: TextEditingController(text: '192.168.1.50'),
        portController: TextEditingController(text: '9100'),
        initiallyConfirmed: true,
      );
      expect(tracker.confirmed, isTrue);
      tracker.dispose();
    });

    test('la case a cocher peut confirmer explicitement', () {
      final tracker = NetworkPrinterConfirmationTracker(
        hostController: TextEditingController(text: '192.168.1.50'),
        portController: TextEditingController(text: '9100'),
      );
      tracker.confirmed = true;
      expect(tracker.confirmed, isTrue);
      tracker.dispose();
    });

    test('modifier le host remet la confirmation a false', () {
      final host = TextEditingController(text: '192.168.1.50');
      final tracker = NetworkPrinterConfirmationTracker(
        hostController: host,
        portController: TextEditingController(text: '9100'),
        initiallyConfirmed: true,
      );
      expect(tracker.confirmed, isTrue);

      host.text = '192.168.1.51';
      expect(tracker.confirmed, isFalse);
      tracker.dispose();
    });

    test('modifier le port remet la confirmation a false', () {
      final port = TextEditingController(text: '9100');
      final tracker = NetworkPrinterConfirmationTracker(
        hostController: TextEditingController(text: '192.168.1.50'),
        portController: port,
        initiallyConfirmed: true,
      );
      expect(tracker.confirmed, isTrue);

      port.text = '9101';
      expect(tracker.confirmed, isFalse);
      tracker.dispose();
    });

    test('notifie onChanged uniquement quand une edition invalide la '
        'confirmation', () {
      var notifications = 0;
      final host = TextEditingController(text: '192.168.1.50');
      final tracker = NetworkPrinterConfirmationTracker(
        hostController: host,
        portController: TextEditingController(text: '9100'),
        initiallyConfirmed: true,
        onChanged: () => notifications++,
      );

      host.text = '192.168.1.99';
      expect(notifications, 1);

      // Une nouvelle edition alors que la confirmation est deja a false ne
      // doit pas re-notifier inutilement.
      host.text = '192.168.1.100';
      expect(notifications, 1);

      // Une confirmation explicite ne declenche pas onChanged (ce n'est pas
      // une invalidation par edition).
      tracker.confirmed = true;
      expect(notifications, 1);

      tracker.dispose();
    });

    test('dispose retire les listeners et arrete les resets automatiques',
        () {
      var notifications = 0;
      final host = TextEditingController(text: '192.168.1.50');
      final tracker = NetworkPrinterConfirmationTracker(
        hostController: host,
        portController: TextEditingController(text: '9100'),
        initiallyConfirmed: true,
        onChanged: () => notifications++,
      );
      tracker.dispose();

      host.text = '192.168.1.200';
      expect(notifications, 0);
      // La valeur interne n'est plus mise a jour une fois le tracker
      // dispose, ce qui est attendu : le dialogue ne doit plus l'utiliser
      // apres dispose().
      expect(tracker.confirmed, isTrue);
    });
  });
}
