import 'package:flutter/widgets.dart';

class KitchenLayoutPolicy {
  const KitchenLayoutPolicy({
    required this.ticketsPerPage,
    required this.columns,
    required this.rows,
    required this.gap,
    required this.padding,
    required this.compact,
  });

  final int ticketsPerPage;
  final int columns;
  final int rows;
  final double gap;
  final EdgeInsets padding;
  final bool compact;

  static KitchenLayoutPolicy fromConstraints(BoxConstraints constraints) {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 1920.0;
    final height =
        constraints.hasBoundedHeight ? constraints.maxHeight : 1080.0;

    return forSize(Size(width, height));
  }

  static KitchenLayoutPolicy forSize(Size size) {
    final width = size.width;
    final height = size.height;

    if (width < 600 || height < 520) {
      return const KitchenLayoutPolicy(
        ticketsPerPage: 1,
        columns: 1,
        rows: 1,
        gap: 12,
        padding: EdgeInsets.all(12),
        compact: true,
      );
    }

    if (width < 900) {
      return const KitchenLayoutPolicy(
        ticketsPerPage: 2,
        columns: 1,
        rows: 2,
        gap: 12,
        padding: EdgeInsets.all(16),
        compact: true,
      );
    }

    if (height < 700 && width < 1280) {
      return const KitchenLayoutPolicy(
        ticketsPerPage: 2,
        columns: 2,
        rows: 1,
        gap: 14,
        padding: EdgeInsets.all(16),
        compact: true,
      );
    }

    return const KitchenLayoutPolicy(
      ticketsPerPage: 4,
      columns: 2,
      rows: 2,
      gap: 16,
      padding: EdgeInsets.all(20),
      compact: false,
    );
  }
}
