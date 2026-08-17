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
        final content = _KitchenItemsContent(
          columns: columns,
          compact: compact,
          oversized: !compact && isOversizedKitchenOrder(items),
        );
        final padding = EdgeInsets.fromLTRB(
          compact ? 12 : 16,
          compact ? 12 : 16,
          compact ? 12 : 16,
          compact ? 8 : 12,
        );

        if (compact) {
          return SingleChildScrollView(
            padding: padding,
            child: content,
          );
        }

        return Padding(
          padding: padding,
          child: content,
        );
      },
    );
  }
}

class _KitchenItemsContent extends StatelessWidget {
  const _KitchenItemsContent({
    required this.columns,
    required this.compact,
    required this.oversized,
  });

  final List<List<OrderItem>> columns;
  final bool compact;
  final bool oversized;

  @override
  Widget build(BuildContext context) {
    final items = columns.singleOrNull;
    final content = items != null
        ? _KitchenItemsColumn(items: items, compact: compact)
        : Row(
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
          );

    if (!oversized) {
      return content;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OversizedKitchenOrderLabel(compact: compact),
        SizedBox(height: compact ? 10 : 12),
        content,
      ],
    );
  }
}

class _OversizedKitchenOrderLabel extends StatelessWidget {
  const _OversizedKitchenOrderLabel({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.tertiary),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 5 : 6,
        ),
        child: Text(
          'COMMANDE VOLUMINEUSE',
          style: KitchenTypography.meta(context).copyWith(
            color: scheme.onTertiaryContainer,
          ),
        ),
      ),
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
  // LOT 4 deterministic rule: switch before shrinking typography.
  return items.length > 5 || _estimatedKitchenOrderVisualLines(items) > 10;
}

bool isOversizedKitchenOrder(List<OrderItem> items) {
  // LOT 4 provisional wall-screen rule: after the two-column fallback, more
  // than 18 estimated visual lines needs a future wider-card layout treatment.
  return _estimatedKitchenOrderVisualLines(items) > 18;
}

int _estimatedKitchenOrderVisualLines(List<OrderItem> items) {
  return items.fold<int>(
    0,
    (total, item) {
      final variantLines = item.variantName?.trim().isNotEmpty ?? false ? 1 : 0;
      return total + 1 + variantLines + item.extras.length;
    },
  );
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

extension _SingleOrNull<T> on List<T> {
  T? get singleOrNull => length == 1 ? first : null;
}
