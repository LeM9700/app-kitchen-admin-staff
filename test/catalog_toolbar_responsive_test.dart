import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('overflow menu pattern renders all four actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PopupMenuButton<String>(
            tooltip: 'Actions catalogue',
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export', child: Text('Export CSV')),
              PopupMenuItem(value: 'import', child: Text('Import CSV')),
              PopupMenuItem(
                value: 'incomplete',
                child: Text('Produits incomplets'),
              ),
              PopupMenuItem(value: 'category', child: Text('Categorie')),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.text('Import CSV'), findsOneWidget);
    expect(find.text('Produits incomplets'), findsOneWidget);
    expect(find.text('Categorie'), findsOneWidget);
  });
}
