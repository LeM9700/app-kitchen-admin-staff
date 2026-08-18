import 'package:flutter_test/flutter_test.dart';
import 'package:app_admin_staff/features/kitchen/domain/kds_screen_key.dart';

void main() {
  group('buildKdsScreenKey', () {
    test('converts "Cuisine principale" to "cuisine-principale"', () {
      expect(buildKdsScreenKey('Cuisine principale'),
          equals('cuisine-principale'));
    });

    test('converts "Comptoir 2" to "comptoir-2"', () {
      expect(buildKdsScreenKey('Comptoir 2'), equals('comptoir-2'));
    });

    test('converts "Écran Chaud 2" to "ecran-chaud-2"', () {
      expect(buildKdsScreenKey('Écran Chaud 2'), equals('ecran-chaud-2'));
    });

    test(
        'converts "  Comptoir   Principal " to "comptoir-principal" (multiple spaces and border)',
        () {
      expect(buildKdsScreenKey('  Comptoir   Principal '),
          equals('comptoir-principal'));
    });

    test(
        'removes special characters from "Salle #1 (VIP)!" and returns valid slug',
        () {
      final result = buildKdsScreenKey('Salle #1 (VIP)!');
      // Verify no characters outside a-z, 0-9, _, - exist
      expect(RegExp(r'^[a-z0-9_\-]+$').hasMatch(result), isTrue);
      // Verify no leading or trailing dashes
      expect(result.startsWith('-'), isFalse);
      expect(result.endsWith('-'), isFalse);
      // Expected result: "salle-1-vip"
      expect(result, equals('salle-1-vip'));
    });

    test('truncates string longer than 64 characters and returns length <= 64',
        () {
      // Create a string that, after normalization, exceeds 64 chars
      final longName = 'a' * 100;
      final result = buildKdsScreenKey(longName);
      expect(result.length, lessThanOrEqualTo(64));
    });

    test('returns "ecran" for empty string', () {
      expect(buildKdsScreenKey(''), equals('ecran'));
    });

    test('returns "ecran" for string with only invalid characters', () {
      expect(buildKdsScreenKey('!!!???'), equals('ecran'));
    });

    // Additional edge case tests
    test('handles accented characters: "Café" becomes "cafe"', () {
      expect(buildKdsScreenKey('Café'), equals('cafe'));
    });

    test(
        'handles mixed case: "CuIsInE PrInCiPaLe" becomes "cuisine-principale"',
        () {
      expect(buildKdsScreenKey('CuIsInE PrInCiPaLe'),
          equals('cuisine-principale'));
    });

    test('preserves underscores in input', () {
      expect(buildKdsScreenKey('Écran_Principal'), equals('ecran_principal'));
    });

    test('preserves numbers in input', () {
      expect(buildKdsScreenKey('Screen 123'), equals('screen-123'));
    });

    test('removes all special characters except dash, underscore, alphanumeric',
        () {
      expect(buildKdsScreenKey('Hello@World#2024!'), equals('helloworld2024'));
    });

    test('handles multiple consecutive spaces correctly', () {
      expect(
          buildKdsScreenKey('Multiple    Spaces'), equals('multiple-spaces'));
    });

    test('trims dashes from beginning and end after filtering', () {
      expect(buildKdsScreenKey('---test---'), equals('test'));
    });

    test('handles tab and newline characters as spaces', () {
      expect(
          buildKdsScreenKey('Test\tTab\nNewline'), equals('test-tab-newline'));
    });

    test('handles very long string with valid and invalid chars at boundary',
        () {
      // Create string that will be 70 chars after processing, ensuring truncation happens correctly
      final longValid = 'abcdefghij' * 7; // 70 chars of valid chars
      final result = buildKdsScreenKey(longValid);
      expect(result.length, lessThanOrEqualTo(64));
      expect(
          result,
          equals(
              'abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcd')); // Should truncate at 64 chars
    });

    test('handles truncation that ends with a dash', () {
      // Create a name that, when truncated at 64 chars, ends with a dash
      // This tests the re-trim logic after truncation
      final name = 'a-' * 50; // "a-a-a-..." - will be >64 chars
      final result = buildKdsScreenKey(name);
      expect(result.length, lessThanOrEqualTo(64));
      expect(result.endsWith('-'), isFalse);
    });

    test('lowercase accents are handled same as uppercase', () {
      expect(buildKdsScreenKey('café'), equals('cafe'));
      expect(buildKdsScreenKey('Café'), equals('cafe'));
    });
  });
}
