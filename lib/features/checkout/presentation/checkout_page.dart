import 'package:app_admin_staff/core/api/idempotency_key.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/core/printing/printer_registry.dart';
import 'package:app_admin_staff/core/printing/receipt_builder.dart';
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/loyalty/data/loyalty_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _cart = <String, _CartLine>{};
  final _tableController = TextEditingController();
  final _deliveryAddressController = TextEditingController();
  final _customerEmailController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _externalReferenceController = TextEditingController();
  final _amountReceivedController = TextEditingController();
  final _promoCodeController = TextEditingController();
  final _loyaltyUserController = TextEditingController();
  final _loyaltyPointsController = TextEditingController();
  final _noteController = TextEditingController();
  LoyaltyAccount? _loyaltyAccount;
  bool _loyaltyLoading = false;
  String _orderType = 'pickup';
  String _paymentMethod = 'cash';
  bool _submitting = false;

  @override
  void dispose() {
    _tableController.dispose();
    _deliveryAddressController.dispose();
    _customerEmailController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _externalReferenceController.dispose();
    _amountReceivedController.dispose();
    _promoCodeController.dispose();
    _loyaltyUserController.dispose();
    _loyaltyPointsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(catalogProductsProvider);
    final tenantStatus = ref.watch(tenantStatusProvider);

    return products.when(
      data: (items) => LayoutBuilder(
        builder: (context, constraints) {
          final compactLayout = constraints.maxWidth < 980;
          final cart = _CartPanel(
            lines: _cart.values.toList(),
            tenantStatus: tenantStatus,
            orderType: _orderType,
            paymentMethod: _paymentMethod,
            tableController: _tableController,
            deliveryAddressController: _deliveryAddressController,
            customerEmailController: _customerEmailController,
            customerNameController: _customerNameController,
            customerPhoneController: _customerPhoneController,
            externalReferenceController: _externalReferenceController,
            amountReceivedController: _amountReceivedController,
            promoCodeController: _promoCodeController,
            loyaltyUserController: _loyaltyUserController,
            loyaltyPointsController: _loyaltyPointsController,
            loyaltyAccount: _loyaltyAccount,
            loyaltyLoading: _loyaltyLoading,
            noteController: _noteController,
            submitting: _submitting,
            onOrderTypeChanged: (value) => setState(() => _orderType = value),
            onPaymentMethodChanged: (value) {
              setState(() => _paymentMethod = value);
            },
            onRemove: (cartKey) => setState(() => _cart.remove(cartKey)),
            onIncrement: (cartKey) {
              setState(
                () => _cart.update(
                  cartKey,
                  (line) => line.copyWith(quantity: line.quantity + 1),
                ),
              );
            },
            onDecrement: (cartKey) {
              setState(() {
                final line = _cart[cartKey];
                if (line == null) {
                  return;
                }
                if (line.quantity <= 1) {
                  _cart.remove(cartKey);
                } else {
                  _cart[cartKey] = line.copyWith(quantity: line.quantity - 1);
                }
              });
            },
            onLookupLoyalty: _lookupLoyalty,
            onSubmit: _submit,
            shrinkWrap: compactLayout,
            physics:
                compactLayout ? const NeverScrollableScrollPhysics() : null,
          );

          final grid = _ProductGrid(
            products: items,
            onAdd: _addProduct,
          );

          if (compactLayout) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SizedBox(height: 420, child: grid),
                const SizedBox(height: 16),
                cart,
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 3, child: grid),
              const VerticalDivider(width: 1),
              SizedBox(width: 420, child: cart),
            ],
          );
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text(error.toString())),
    );
  }

  Future<void> _submit() async {
    if (_cart.isEmpty) {
      _snack('Panier vide');
      return;
    }
    if (_orderType == 'delivery' &&
        _deliveryAddressController.text.trim().isEmpty) {
      _snack('Adresse requise pour une livraison');
      return;
    }
    if ({'external_terminal', 'cash_register'}.contains(_paymentMethod) &&
        _externalReferenceController.text.trim().isEmpty) {
      _snack('Reference externe requise pour ce paiement');
      return;
    }
    if (_parseInt(_loyaltyPointsController.text) != null &&
        _parseInt(_loyaltyUserController.text) == null) {
      _snack('User ID fidelite requis pour utiliser des points');
      return;
    }

    setState(() => _submitting = true);
    try {
      final draft = ManualOrderDraft(
        idempotencyKey: _newIdempotencyKey(),
        orderType: _orderType,
        tableNumber: _emptyToNull(_tableController.text),
        deliveryAddress: _emptyToNull(_deliveryAddressController.text),
        customerEmail: _emptyToNull(_customerEmailController.text),
        customerName: _emptyToNull(_customerNameController.text),
        customerPhone: _emptyToNull(_customerPhoneController.text),
        paymentMethod: _paymentMethod,
        externalReference: _emptyToNull(_externalReferenceController.text),
        amountReceived: _parseAmount(_amountReceivedController.text),
        promoCode: _emptyToNull(_promoCodeController.text),
        loyaltyUserId: _parseInt(_loyaltyUserController.text),
        loyaltyPointsToUse: _parseInt(_loyaltyPointsController.text),
        note: _emptyToNull(_noteController.text),
        items: _cart.values
            .map(
              (line) => ManualOrderLine(
                productId: line.product.id,
                variantId: line.variant?.id,
                quantity: line.quantity,
                extras: line.extras
                    .map((extra) => ManualOrderExtraLine(extraId: extra.id))
                    .toList(),
              ),
            )
            .toList(),
      );
      final result =
          await ref.read(ordersRepositoryProvider).createManualOrder(draft);
      final receipt = ReceiptBuilder.customerReceipt(result.order);
      final tickets = ReceiptBuilder.kitchenTickets(result.order);
      ref.read(printJobsProvider.notifier).enqueue(receipt);
      for (final ticket in tickets) {
        ref.read(printJobsProvider.notifier).enqueue(ticket);
      }
      ref.invalidate(activeOrdersProvider);
      ref.invalidate(paymentsProvider);
      ref.invalidate(paymentsSummaryProvider);
      setState(() {
        _cart.clear();
        _noteController.clear();
        _externalReferenceController.clear();
        _amountReceivedController.clear();
        _promoCodeController.clear();
        _loyaltyUserController.clear();
        _loyaltyPointsController.clear();
        _loyaltyAccount = null;
      });
      _snack('Commande #${result.order.id} encaissee');
      if (mounted) {
        await _showReceipt(result);
      }
    } catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _newIdempotencyKey() {
    return IdempotencyKey.generate('manual');
  }

  Future<void> _addProduct(CatalogProduct product) async {
    CatalogProduct detail;
    try {
      detail = await ref.read(catalogRepositoryProvider).getProduct(product.id);
    } catch (error) {
      _snack(error.toString());
      return;
    }
    if (!mounted) {
      return;
    }

    final selection = await _selectionDialog(detail);
    if (selection == null) {
      return;
    }
    setState(() {
      _cart.update(
        selection.key,
        (line) => line.copyWith(quantity: line.quantity + 1),
        ifAbsent: () => _CartLine(
          product: detail,
          quantity: 1,
          variant: selection.variant,
          extras: selection.extras,
        ),
      );
    });
  }

  Future<_CartSelection?> _selectionDialog(CatalogProduct product) async {
    final variants =
        product.variants.where((variant) => variant.isActive).toList();
    final extras = product.extras.where((extra) => extra.isActive).toList();
    if (variants.isEmpty && extras.isEmpty) {
      return _CartSelection(product: product);
    }

    CatalogVariant? selectedVariant = variants.isEmpty ? null : variants.first;
    final selectedExtras = <int>{};
    return showDialog<_CartSelection>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final activeExtras = extras
              .where((extra) => selectedExtras.contains(extra.id))
              .toList();
          final selection = _CartSelection(
            product: product,
            variant: selectedVariant,
            extras: activeExtras,
          );
          return AlertDialog(
            title: Text(product.name),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (variants.isNotEmpty) ...[
                    Text(
                      'Variante',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...variants.map((variant) {
                      final selected = selectedVariant?.id == variant.id;
                      return ListTile(
                        selected: selected,
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(variant.name),
                        subtitle: Text(
                          formatMoney(product.basePrice + variant.priceDelta),
                        ),
                        onTap: () {
                          setState(() {
                            selectedVariant = variant;
                          });
                        },
                      );
                    }),
                    const Divider(),
                  ],
                  if (extras.isNotEmpty) ...[
                    Text(
                      'Extras',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...extras.map((extra) {
                      return CheckboxListTile(
                        value: selectedExtras.contains(extra.id),
                        title: Text(extra.name),
                        subtitle: Text(formatMoney(extra.price)),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              selectedExtras.add(extra.id);
                            } else {
                              selectedExtras.remove(extra.id);
                            }
                          });
                        },
                      );
                    }),
                  ],
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Prix ligne'),
                    trailing: Text(formatMoney(selection.unitPrice)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, selection),
                icon: const Icon(Icons.add_shopping_cart_outlined),
                label: const Text('Ajouter'),
              ),
            ],
          );
        },
      ),
    );
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  double? _parseAmount(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  int? _parseInt(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }

  Future<void> _lookupLoyalty() async {
    final userId = _parseInt(_loyaltyUserController.text);
    if (userId == null) {
      _snack('User ID fidelite invalide');
      return;
    }
    setState(() => _loyaltyLoading = true);
    try {
      final account = await ref.read(loyaltyRepositoryProvider).account(userId);
      if (!mounted) {
        return;
      }
      setState(() => _loyaltyAccount = account);
    } catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _loyaltyLoading = false);
      }
    }
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showReceipt(ManualOrderResult result) async {
    final receipt = ReceiptBuilder.customerReceipt(result.order);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Recu #${result.order.id}'),
        content: SizedBox(
          width: 420,
          child: SelectableText(receipt.content),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({
    required this.products,
    required this.onAdd,
  });

  final List<CatalogProduct> products;
  final Future<void> Function(CatalogProduct product) onAdd;

  @override
  Widget build(BuildContext context) {
    final availableProducts = products
        .where((product) => product.isActive && product.available != false)
        .toList();
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 132,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: availableProducts.length,
      itemBuilder: (context, index) {
        final product = availableProducts[index];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              onAdd(product);
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Text(formatMoney(product.basePrice)),
                      const Spacer(),
                      const Icon(Icons.add_circle_outline),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.lines,
    required this.tenantStatus,
    required this.orderType,
    required this.paymentMethod,
    required this.tableController,
    required this.deliveryAddressController,
    required this.customerEmailController,
    required this.customerNameController,
    required this.customerPhoneController,
    required this.externalReferenceController,
    required this.amountReceivedController,
    required this.promoCodeController,
    required this.loyaltyUserController,
    required this.loyaltyPointsController,
    required this.loyaltyAccount,
    required this.loyaltyLoading,
    required this.noteController,
    required this.submitting,
    required this.onOrderTypeChanged,
    required this.onPaymentMethodChanged,
    required this.onRemove,
    required this.onIncrement,
    required this.onDecrement,
    required this.onLookupLoyalty,
    required this.onSubmit,
    this.shrinkWrap = false,
    this.physics,
  });

  final List<_CartLine> lines;
  final AsyncValue<TenantStatus> tenantStatus;
  final String orderType;
  final String paymentMethod;
  final TextEditingController tableController;
  final TextEditingController deliveryAddressController;
  final TextEditingController customerEmailController;
  final TextEditingController customerNameController;
  final TextEditingController customerPhoneController;
  final TextEditingController externalReferenceController;
  final TextEditingController amountReceivedController;
  final TextEditingController promoCodeController;
  final TextEditingController loyaltyUserController;
  final TextEditingController loyaltyPointsController;
  final LoyaltyAccount? loyaltyAccount;
  final bool loyaltyLoading;
  final TextEditingController noteController;
  final bool submitting;
  final ValueChanged<String> onOrderTypeChanged;
  final ValueChanged<String> onPaymentMethodChanged;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onIncrement;
  final ValueChanged<String> onDecrement;
  final VoidCallback onLookupLoyalty;
  final VoidCallback onSubmit;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final total = lines.fold<double>(0, (sum, line) => sum + line.total);

    return ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: shrinkWrap,
      physics: physics,
      children: [
        Text(
          'Commande manuelle',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        tenantStatus.maybeWhen(
          data: (value) => value.isOpen
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    leading: Icon(
                      Icons.lock_clock_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Restaurant ferme'),
                    subtitle: Text(
                      value.message ?? 'Hors horaires ou fermeture manuelle',
                    ),
                  ),
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'pickup',
              icon: Icon(Icons.shopping_bag_outlined),
              label: Text('Emporter'),
            ),
            ButtonSegment(
              value: 'dine_in',
              icon: Icon(Icons.table_restaurant_outlined),
              label: Text('Sur place'),
            ),
            ButtonSegment(
              value: 'delivery',
              icon: Icon(Icons.delivery_dining_outlined),
              label: Text('Livraison'),
            ),
          ],
          selected: {orderType},
          onSelectionChanged: (value) => onOrderTypeChanged(value.first),
        ),
        const SizedBox(height: 12),
        if (orderType == 'dine_in')
          TextField(
            controller: tableController,
            decoration: const InputDecoration(
              labelText: 'Table',
              prefixIcon: Icon(Icons.table_restaurant_outlined),
            ),
          ),
        if (orderType == 'delivery')
          TextField(
            controller: deliveryAddressController,
            decoration: const InputDecoration(
              labelText: 'Adresse de livraison',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: customerNameController,
          decoration: const InputDecoration(
            labelText: 'Nom client',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: customerEmailController,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: customerPhoneController,
                decoration: const InputDecoration(labelText: 'Telephone'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Panier', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (lines.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.shopping_cart_outlined),
            title: Text('Aucun produit'),
          )
        else
          ...lines.map((line) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(line.product.name),
              subtitle: Text(
                [
                  formatMoney(line.unitPrice),
                  if (line.variant != null) line.variant!.name,
                  if (line.extras.isNotEmpty)
                    line.extras.map((extra) => '+ ${extra.name}').join(', '),
                ].join(' - '),
              ),
              leading: IconButton(
                tooltip: 'Retirer',
                onPressed: () => onRemove(line.key),
                icon: const Icon(Icons.delete_outline),
              ),
              trailing: SizedBox(
                width: 132,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Moins',
                      onPressed: () => onDecrement(line.key),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(line.quantity.toString()),
                    IconButton(
                      tooltip: 'Plus',
                      onPressed: () => onIncrement(line.key),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
            );
          }),
        const Divider(),
        Row(
          children: [
            Text(
              'Total serveur estime',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            Text(
              formatMoney(total),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: promoCodeController,
          decoration: const InputDecoration(
            labelText: 'Code promo',
            prefixIcon: Icon(Icons.sell_outlined),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: loyaltyUserController,
                decoration: const InputDecoration(
                  labelText: 'User ID fidelite',
                  prefixIcon: Icon(Icons.loyalty_outlined),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Consulter points',
              onPressed: loyaltyLoading ? null : onLookupLoyalty,
              icon: loyaltyLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
            ),
          ],
        ),
        if (loyaltyAccount != null) ...[
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text('${loyaltyAccount!.points} points disponibles'),
            subtitle:
                Text('Valeur ${formatMoney(loyaltyAccount!.pointValueEuros)}'),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: loyaltyPointsController,
          decoration: const InputDecoration(
            labelText: 'Points a utiliser',
            prefixIcon: Icon(Icons.redeem_outlined),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'cash',
              icon: Icon(Icons.payments),
              label: Text('Cash'),
            ),
            ButtonSegment(
              value: 'external_terminal',
              icon: Icon(Icons.credit_card),
              label: Text('TPE'),
            ),
            ButtonSegment(
              value: 'cash_register',
              icon: Icon(Icons.point_of_sale),
              label: Text('Caisse'),
            ),
          ],
          selected: {paymentMethod},
          onSelectionChanged: (value) => onPaymentMethodChanged(value.first),
        ),
        const SizedBox(height: 12),
        if ({'external_terminal', 'cash_register'}.contains(paymentMethod))
          TextField(
            controller: externalReferenceController,
            decoration: const InputDecoration(
              labelText: 'Reference externe',
              prefixIcon: Icon(Icons.tag_outlined),
            ),
          ),
        if (paymentMethod == 'cash') ...[
          TextField(
            controller: amountReceivedController,
            decoration: const InputDecoration(
              labelText: 'Montant recu',
              prefixIcon: Icon(Icons.euro_outlined),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: noteController,
          decoration: const InputDecoration(
            labelText: 'Note cuisine',
            prefixIcon: Icon(Icons.notes_outlined),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: submitting ? null : onSubmit,
          icon: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: const Text('Encaisser'),
        ),
      ],
    );
  }
}

class _CartLine {
  const _CartLine({
    required this.product,
    required this.quantity,
    this.variant,
    this.extras = const [],
  });

  final CatalogProduct product;
  final int quantity;
  final CatalogVariant? variant;
  final List<CatalogExtra> extras;

  String get key {
    final extraIds = extras.map((extra) => extra.id).toList()..sort();
    return [
      product.id,
      variant?.id ?? 'base',
      ...extraIds,
    ].join(':');
  }

  double get unitPrice {
    return product.basePrice +
        (variant?.priceDelta ?? 0) +
        extras.fold<double>(0, (sum, extra) => sum + extra.price);
  }

  double get total => unitPrice * quantity;

  _CartLine copyWith({int? quantity}) {
    return _CartLine(
      product: product,
      quantity: quantity ?? this.quantity,
      variant: variant,
      extras: extras,
    );
  }
}

class _CartSelection {
  const _CartSelection({
    required this.product,
    this.variant,
    this.extras = const [],
  });

  final CatalogProduct product;
  final CatalogVariant? variant;
  final List<CatalogExtra> extras;

  String get key {
    final extraIds = extras.map((extra) => extra.id).toList()..sort();
    return [
      product.id,
      variant?.id ?? 'base',
      ...extraIds,
    ].join(':');
  }

  double get unitPrice {
    return product.basePrice +
        (variant?.priceDelta ?? 0) +
        extras.fold<double>(0, (sum, extra) => sum + extra.price);
  }
}
