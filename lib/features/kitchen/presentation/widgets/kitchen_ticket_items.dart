import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter/material.dart';

class KitchenTicketItems extends StatelessWidget {
  const KitchenTicketItems({
    required this.items,
    this.compact = false,
    super.key,
  });

  final List<OrderItem> items;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'AUCUN PRODUIT POUR CE POSTE',
          textAlign: TextAlign.center,
          style: KitchenTypography.meta(context),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns =
            constraints.maxWidth >= 540 && _shouldUseTwoColumns(items);
        final columns = useTwoColumns ? _splitForTwoColumns(items) : [items];

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            compact ? 12 : 16,
            compact ? 12 : 16,
            compact ? 8 : 12,
          ),
          child: useTwoColumns
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _KitchenItemsColumn(
                        items: columns[0],
                        compact: compact,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _KitchenItemsColumn(
                        items: columns[1],
                        compact: compact,
                      ),
                    ),
                  ],
                )
              : _KitchenItemsColumn(items: items, compact: compact),
        );
      },
    );
  }
}

class _KitchenItemsColumn extends StatelessWidget {
  const _KitchenItemsColumn({
    required this.items,
    required this.compact,
  });

  final List<OrderItem> items;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _KitchenItemBlock(item: items[index], compact: compact),
          if (index < items.length - 1) SizedBox(height: compact ? 12 : 16),
        ],
      ],
    );
  }
}

class _KitchenItemBlock extends StatelessWidget {
  const _KitchenItemBlock({
    required this.item,
    required this.compact,
  });

  final OrderItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final variantName = item.variantName?.trim();
    final extras = item.extras.where((extra) => extra.name.trim().isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${item.quantity} × ${_productName(item)}',
          softWrap: true,
          style: KitchenTypography.product(context, compact: compact),
        ),
        if (variantName != null && variantName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              variantName.toUpperCase(),
              softWrap: true,
              style: KitchenTypography.variant(context, compact: compact),
            ),
          ),
        ],
        for (final extra in extras) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              _extraLabel(extra),
              softWrap: true,
              style: KitchenTypography.extra(context, compact: compact),
            ),
          ),
        ],
      ],
    );
  }

  String _productName(OrderItem item) {
    final productName = item.productName?.trim();
    if (productName == null || productName.isEmpty) {
      return 'PRODUIT #${item.productId}';
    }

    return productName.toUpperCase();
  }

  String _extraLabel(OrderItemExtra extra) {
    if (extra.quantity > 1) {
      return '+ ${extra.quantity} × ${extra.name}';
    }

    return '+ ${extra.name}';
  }
}

bool _shouldUseTwoColumns(List<OrderItem> items) {
  final visualLines = items.fold<int>(
    0,
    (total, item) {
      final variantLines = item.variantName?.trim().isNotEmpty ?? false ? 1 : 0;
      return total + 1 + variantLines + item.extras.length;
    },
  );

  // LOT 4 deterministic rule: switch before shrinking typography.
  return items.length > 5 || visualLines > 10;
}

List<List<OrderItem>> _splitForTwoColumns(List<OrderItem> items) {
  final left = <OrderItem>[];
  final right = <OrderItem>[];
  var leftLines = 0;
  var rightLines = 0;

  for (final item in items) {
    final lines = 1 +
        ((item.variantName?.trim().isNotEmpty ?? false) ? 1 : 0) +
        item.extras.length;
    if (leftLines <= rightLines) {
      left.add(item);
      leftLines += lines;
    } else {
      right.add(item);
      rightLines += lines;
    }
  }

  return [left, right];
}
