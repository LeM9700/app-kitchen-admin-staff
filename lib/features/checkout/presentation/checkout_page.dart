import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/api/idempotency_key.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/printing/printer_registry.dart';
import 'package:app_admin_staff/core/printing/receipt_builder.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/feedback/app_feedback.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_elevation.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/checkout/application/checkout_validation.dart';
import 'package:app_admin_staff/features/checkout/domain/checkout_cart.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/loyalty/data/loyalty_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _posBackground = Color(0xFFE8E2D8);
const _posSurface = Color(0xFFF8F4EC);
const _posSurfaceRaised = Color(0xFFFFFCF6);
const _posInk = Color(0xFF24211C);
const _posMuted = Color(0xFF6B655B);
const _posLine = Color(0xFFD8D0C3);
const _allCategories = '__all__';

class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _cart = <String, CheckoutCartLine>{};
  final _productDetails = <int, CatalogProduct>{};
  final _searchController = TextEditingController();
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
  bool _submitting = false;
  String _orderType = 'pickup';
  String _paymentMethod = 'cash';
  String _category = _allCategories;
  String? _validationMessage;
  int? _cartEstablishmentId;

  @override
  void dispose() {
    _searchController.dispose();
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
    ref.listen<AsyncValue<Establishment?>>(currentEstablishmentProvider,
        (previous, next) {
      final previousId = previous?.valueOrNull?.id;
      final nextId = next.valueOrNull?.id;
      if (previousId == null || nextId == null || previousId == nextId) {
        return;
      }
      _productDetails.clear();
      if (_cart.isEmpty) {
        _cartEstablishmentId = nextId;
        return;
      }
      setState(() {
        _cart.clear();
        _cartEstablishmentId = nextId;
        _validationMessage = null;
      });
      _snack('Panier vide apres changement d etablissement');
    });

    final products = ref.watch(catalogProductsProvider);
    final tenantStatus = ref.watch(tenantStatusProvider);
    final currentEstablishment = ref.watch(currentEstablishmentProvider);
    final online = ref.watch(onlineStatusProvider).valueOrNull ?? true;
    final permissions = ref.watch(currentPermissionSetProvider);
    final canUseTerminal = permissions.can(AppPermission.paymentsTerminal);

    return NeumorphicIntensityScope(
      intensity: NeumorphicIntensity.subtle,
      child: ColoredBox(
        color: _posBackground,
        child: SafeArea(
          child: products.when(
            loading: _CatalogSkeleton.new,
            error: (error, stackTrace) => AppFeedback(
              kind: AppFeedbackKind.error,
              title: 'Catalogue indisponible',
              message: 'Impossible de charger les produits pour la caisse.',
              onRetry: () => ref.invalidate(catalogProductsProvider),
            ),
            data: (items) => LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = constraints.maxWidth >= 900;
                final total = checkoutCartTotal(_cart.values);
                final cart = _buildCartPanel(
                  tenantStatus: tenantStatus,
                  online: online,
                  canUseTerminal: canUseTerminal,
                  sideBySide: sideBySide,
                );
                final catalog = _CheckoutCatalog(
                  products: _visibleProducts(items),
                  allProducts: _availableProducts(items),
                  selectedCategory: _category,
                  searchController: _searchController,
                  onSearchChanged: (_) => setState(() {}),
                  onCategoryChanged: (value) {
                    setState(() => _category = value);
                  },
                  onAdd: _addProduct,
                );

                return Column(
                  children: [
                    _CheckoutHeader(
                      establishmentName:
                          currentEstablishment.valueOrNull?.name ?? 'Cuisine',
                      tenantStatus: tenantStatus,
                      online: online,
                      orderType: _orderType,
                      onOrderTypeChanged: (value) {
                        setState(() {
                          _orderType = value;
                          _validationMessage = null;
                        });
                      },
                    ),
                    Expanded(
                      child: sideBySide
                          ? Row(
                              children: [
                                Expanded(flex: 7, child: catalog),
                                Container(width: 1, color: _posLine),
                                SizedBox(width: 440, child: cart),
                              ],
                            )
                          : Stack(
                              children: [
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 92),
                                    child: catalog,
                                  ),
                                ),
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 12,
                                  child: _MobileCartBar(
                                    itemCount: _cart.values.fold<int>(
                                      0,
                                      (sum, line) => sum + line.quantity,
                                    ),
                                    total: total,
                                    onOpen: () => _openMobileCart(
                                      tenantStatus: tenantStatus,
                                      online: online,
                                      canUseTerminal: canUseTerminal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCartPanel({
    required AsyncValue<TenantStatus> tenantStatus,
    required bool online,
    required bool canUseTerminal,
    required bool sideBySide,
  }) {
    return _CartPanel(
      lines: _cart.values.toList(),
      tenantStatus: tenantStatus,
      online: online,
      canUseTerminal: canUseTerminal,
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
      validationMessage: _validationMessage,
      onChanged: () => setState(() => _validationMessage = null),
      onPaymentMethodChanged: (value) {
        setState(() {
          _paymentMethod = value;
          _validationMessage = null;
        });
      },
      onRemove: (cartKey) {
        setState(() {
          _cart.remove(cartKey);
          _validationMessage = null;
        });
      },
      onIncrement: (cartKey) {
        setState(() {
          _cart.update(
            cartKey,
            (line) => line.copyWith(quantity: line.quantity + 1),
          );
          _validationMessage = null;
        });
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
          _validationMessage = null;
        });
      },
      onLookupLoyalty: _lookupLoyalty,
      onSubmit: _submit,
      stickyFooter: sideBySide,
    );
  }

  List<CatalogProduct> _availableProducts(List<CatalogProduct> products) {
    return products
        .where((product) => product.isActive && product.available != false)
        .toList();
  }

  List<CatalogProduct> _visibleProducts(List<CatalogProduct> products) {
    final query = _searchController.text.trim().toLowerCase();
    return _availableProducts(products).where((product) {
      if (_category != _allCategories &&
          (product.categoryName ?? '').trim() != _category) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final searchable = [
        product.name,
        product.description,
        product.categoryName,
      ].whereType<String>().join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  Future<void> _openMobileCart({
    required AsyncValue<TenantStatus> tenantStatus,
    required bool online,
    required bool canUseTerminal,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _posBackground,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.94,
        child: SafeArea(
          child: _buildCartPanel(
            tenantStatus: tenantStatus,
            online: online,
            canUseTerminal: canUseTerminal,
            sideBySide: false,
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    final validation = _validate();
    if (!validation.isValid) {
      setState(() => _validationMessage = validation.message);
      return;
    }

    setState(() => _submitting = true);
    try {
      final currentEstablishmentId =
          ref.read(currentEstablishmentProvider).valueOrNull?.id;
      final draft = ManualOrderDraft(
        idempotencyKey: _newIdempotencyKey(),
        orderType: _orderType,
        establishmentId: currentEstablishmentId,
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
      setState(_resetAfterSale);
      if (mounted) {
        await _showSuccessSheet(
          result: result,
          receiptContent: receipt.content,
          kitchenTicketCount: tickets.length,
        );
      }
    } catch (error) {
      setState(() {
        _validationMessage =
            'Encaissement impossible. Verifiez puis reessayez.';
      });
      _snack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  CheckoutValidationResult _validate() {
    final tenant = ref.read(tenantStatusProvider).valueOrNull;
    final currentEstablishmentId =
        ref.read(currentEstablishmentProvider).valueOrNull?.id;
    return validateCheckout(
      CheckoutValidationInput(
        hasItems: _cart.isNotEmpty,
        orderType: _orderType,
        paymentMethod: _paymentMethod,
        deliveryAddress: _deliveryAddressController.text,
        externalReference: _externalReferenceController.text,
        loyaltyUserId: _parseInt(_loyaltyUserController.text),
        loyaltyPointsToUse: _parseInt(_loyaltyPointsController.text),
        total: checkoutCartTotal(_cart.values),
        amountReceived: _parseAmount(_amountReceivedController.text),
        isOnline: ref.read(onlineStatusProvider).valueOrNull ?? true,
        isRestaurantOpen: tenant?.isOpen ?? true,
        cartEstablishmentId: _cartEstablishmentId,
        currentEstablishmentId: currentEstablishmentId,
      ),
    );
  }

  void _resetAfterSale() {
    _cart.clear();
    _noteController.clear();
    _externalReferenceController.clear();
    _amountReceivedController.clear();
    _promoCodeController.clear();
    _loyaltyUserController.clear();
    _loyaltyPointsController.clear();
    _loyaltyAccount = null;
    _validationMessage = null;
    _cartEstablishmentId =
        ref.read(currentEstablishmentProvider).valueOrNull?.id;
  }

  String _newIdempotencyKey() {
    return IdempotencyKey.generate('manual');
  }

  Future<void> _addProduct(CatalogProduct product) async {
    if (!product.isActive || product.available == false) {
      return;
    }
    final establishmentId =
        ref.read(currentEstablishmentProvider).valueOrNull?.id;
    CatalogProduct detail;
    try {
      detail = _productDetails[product.id] ??
          await ref.read(catalogRepositoryProvider).getProduct(product.id);
      _productDetails[product.id] = detail;
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
      _cartEstablishmentId ??= establishmentId;
      _cart.update(
        selection.key,
        (line) => line.copyWith(quantity: line.quantity + 1),
        ifAbsent: () => CheckoutCartLine(
          product: detail,
          quantity: 1,
          variant: selection.variant,
          extras: selection.extras,
        ),
      );
      _validationMessage = null;
    });
  }

  Future<CheckoutCartSelection?> _selectionDialog(
    CatalogProduct product,
  ) async {
    final variants =
        product.variants.where((variant) => variant.isActive).toList();
    final extras = product.extras.where((extra) => extra.isActive).toList();
    if (variants.isEmpty && extras.isEmpty) {
      return CheckoutCartSelection(product: product);
    }

    CatalogVariant? selectedVariant = variants.isEmpty ? null : variants.first;
    final selectedExtras = <int>{};
    return showDialog<CheckoutCartSelection>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final activeExtras = extras
              .where((extra) => selectedExtras.contains(extra.id))
              .toList();
          final selection = CheckoutCartSelection(
            product: product,
            variant: selectedVariant,
            extras: activeExtras,
          );
          return Dialog(
            insetPadding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      product.name,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    if (variants.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const _SectionLabel('Taille'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final variant in variants)
                            _ChoicePad(
                              label: variant.name,
                              value: formatMoney(
                                product.basePrice + variant.priceDelta,
                              ),
                              selected: selectedVariant?.id == variant.id,
                              onTap: () => setDialogState(
                                () => selectedVariant = variant,
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (extras.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const _SectionLabel('Supplements'),
                      const SizedBox(height: 8),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final extra in extras)
                                _ChoicePad(
                                  label: '+ ${extra.name}',
                                  value: formatMoney(extra.price),
                                  selected: selectedExtras.contains(extra.id),
                                  onTap: () => setDialogState(() {
                                    if (selectedExtras.contains(extra.id)) {
                                      selectedExtras.remove(extra.id);
                                    } else {
                                      selectedExtras.add(extra.id);
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _posBackground,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          const Text('Prix ligne'),
                          const Spacer(),
                          Text(
                            formatMoney(selection.unitPrice),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(context, selection),
                            icon: const Icon(Icons.add_shopping_cart_outlined),
                            label: const Text('Ajouter au panier'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _lookupLoyalty() async {
    final userId = _parseInt(_loyaltyUserController.text);
    if (userId == null) {
      setState(() => _validationMessage = 'User ID fidelite invalide');
      return;
    }
    setState(() => _loyaltyLoading = true);
    try {
      final account = await ref.read(loyaltyRepositoryProvider).account(userId);
      if (!mounted) {
        return;
      }
      setState(() {
        _loyaltyAccount = account;
        _validationMessage = null;
      });
    } catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _loyaltyLoading = false);
      }
    }
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

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showSuccessSheet({
    required ManualOrderResult result,
    required String receiptContent,
    required int kitchenTicketCount,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _posSurface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.check_circle,
                size: 52,
                color: AppColors.success,
              ),
              const SizedBox(height: 12),
              Text(
                'Commande #${result.order.id} encaissee',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                formatMoney(result.order.total),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              _SuccessRow(
                icon: Icons.payments_outlined,
                label: _paymentLabel(_paymentMethod),
              ),
              const _SuccessRow(
                icon: Icons.receipt_long_outlined,
                label: 'Recu client ajoute a l impression',
              ),
              _SuccessRow(
                icon: Icons.soup_kitchen_outlined,
                label: kitchenTicketCount == 0
                    ? 'Aucun ticket cuisine requis'
                    : '$kitchenTicketCount ticket(s) cuisine envoyes',
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showReceiptText(receiptContent),
                      icon: const Icon(Icons.article_outlined),
                      label: const Text('Voir le recu'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Nouvelle commande'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReceiptText(String receiptContent) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recu client'),
        content: SizedBox(
          width: 420,
          child: SelectableText(receiptContent),
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

class _CheckoutHeader extends StatelessWidget {
  const _CheckoutHeader({
    required this.establishmentName,
    required this.tenantStatus,
    required this.online,
    required this.orderType,
    required this.onOrderTypeChanged,
  });

  final String establishmentName;
  final AsyncValue<TenantStatus> tenantStatus;
  final bool online;
  final String orderType;
  final ValueChanged<String> onOrderTypeChanged;

  @override
  Widget build(BuildContext context) {
    final isOpen = tenantStatus.valueOrNull?.isOpen ?? true;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Caisse',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900, color: _posInk),
        ),
        const SizedBox(height: 2),
        Text(
          establishmentName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: _posMuted),
        ),
      ],
    );
    final statuses = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusChip(
          label: online ? 'En ligne' : 'Hors ligne',
          icon: online ? Icons.wifi_outlined : Icons.wifi_off_outlined,
          color: online ? AppColors.success : AppColors.danger,
        ),
        const SizedBox(width: 8),
        _StatusChip(
          label: isOpen ? 'Ouvert' : 'Ferme',
          icon: isOpen ? Icons.lock_open_outlined : Icons.lock_clock_outlined,
          color: isOpen ? AppColors.success : AppColors.warning,
        ),
      ],
    );
    final selector = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: _OrderTypeSelector(
        value: orderType,
        onChanged: onOrderTypeChanged,
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: const BoxDecoration(
        color: _posSurface,
        border: Border(bottom: BorderSide(color: _posLine)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 10),
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: statuses,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                selector,
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 180, child: title),
              const SizedBox(width: 18),
              Expanded(child: selector),
              const SizedBox(width: 12),
              statuses,
            ],
          );
        },
      ),
    );
  }
}

class _CheckoutCatalog extends StatelessWidget {
  const _CheckoutCatalog({
    required this.products,
    required this.allProducts,
    required this.selectedCategory,
    required this.searchController,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onAdd,
  });

  final List<CatalogProduct> products;
  final List<CatalogProduct> allProducts;
  final String selectedCategory;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onCategoryChanged;
  final Future<void> Function(CatalogProduct product) onAdd;

  @override
  Widget build(BuildContext context) {
    final categories = allProducts
        .map((product) => product.categoryName?.trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Rechercher un produit...',
                  prefixIcon: Icon(Icons.search),
                  filled: true,
                  fillColor: _posSurfaceRaised,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _CategoryButton(
                      label: 'Tous',
                      selected: selectedCategory == _allCategories,
                      onTap: () => onCategoryChanged(_allCategories),
                    ),
                    for (final category in categories)
                      _CategoryButton(
                        label: category,
                        selected: selectedCategory == category,
                        onTap: () => onCategoryChanged(category),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? const AppFeedback(
                  kind: AppFeedbackKind.empty,
                  title: 'Aucun produit disponible',
                  message: 'Aucun produit actif ne correspond au filtre.',
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 230,
                    mainAxisExtent: 132,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return _ProductTile(
                      product: product,
                      onTap: () => onAdd(product),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.onTap,
  });

  final CatalogProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ajouter ${product.name}',
      child: DsCard(
        padding: const EdgeInsets.all(14),
        backgroundColor: _posSurfaceRaised,
        borderColor: _posLine,
        borderRadius: AppRadius.md,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((product.categoryName ?? '').isNotEmpty)
              Text(
                product.categoryName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: _posMuted, fontWeight: FontWeight.w800),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                product.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: _posInk,
                    ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(product.basePrice),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppColors.accent,
                          ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.add_circle, color: AppColors.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.lines,
    required this.tenantStatus,
    required this.online,
    required this.canUseTerminal,
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
    required this.validationMessage,
    required this.onChanged,
    required this.onPaymentMethodChanged,
    required this.onRemove,
    required this.onIncrement,
    required this.onDecrement,
    required this.onLookupLoyalty,
    required this.onSubmit,
    required this.stickyFooter,
  });

  final List<CheckoutCartLine> lines;
  final AsyncValue<TenantStatus> tenantStatus;
  final bool online;
  final bool canUseTerminal;
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
  final String? validationMessage;
  final VoidCallback onChanged;
  final ValueChanged<String> onPaymentMethodChanged;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onIncrement;
  final ValueChanged<String> onDecrement;
  final VoidCallback onLookupLoyalty;
  final VoidCallback onSubmit;
  final bool stickyFooter;

  @override
  Widget build(BuildContext context) {
    final total = checkoutCartTotal(lines);
    final isOpen = tenantStatus.valueOrNull?.isOpen ?? true;
    final amountReceived = _parsePanelAmount(amountReceivedController.text);
    final change = amountReceived == null ? null : amountReceived - total;
    final blocked = submitting || lines.isEmpty || !online || !isOpen;

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text(
              'Commande',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            Text(
              '${lines.fold<int>(0, (sum, line) => sum + line.quantity)} article(s)',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: _posMuted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!online)
          const _WarningBanner(
            icon: Icons.wifi_off_outlined,
            title: 'Hors ligne',
            message: 'Encaissement bloque tant que le serveur ne confirme pas.',
          ),
        if (!isOpen)
          _WarningBanner(
            icon: Icons.lock_clock_outlined,
            title: 'Restaurant ferme',
            message: tenantStatus.valueOrNull?.message ??
                'Les commandes manuelles sont indisponibles.',
          ),
        _ContextSection(
          orderType: orderType,
          tableController: tableController,
          deliveryAddressController: deliveryAddressController,
          customerEmailController: customerEmailController,
          customerNameController: customerNameController,
          customerPhoneController: customerPhoneController,
          onChanged: onChanged,
        ),
        const SizedBox(height: 12),
        _CartLinesSection(
          lines: lines,
          onRemove: onRemove,
          onIncrement: onIncrement,
          onDecrement: onDecrement,
        ),
        const SizedBox(height: 12),
        _ExpandableSection(
          title: 'Ajouter un code promo',
          icon: Icons.sell_outlined,
          child: TextField(
            controller: promoCodeController,
            onChanged: (_) => onChanged(),
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Code promo'),
          ),
        ),
        const SizedBox(height: 10),
        _ExpandableSection(
          title: 'Fidelite',
          icon: Icons.loyalty_outlined,
          subtitle: loyaltyAccount == null
              ? 'Aucun client fidelite'
              : '${loyaltyAccount!.points} points disponibles',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: loyaltyUserController,
                      onChanged: (_) => onChanged(),
                      decoration: const InputDecoration(
                        labelText: 'User ID fidelite',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox.square(
                    dimension: 48,
                    child: FilledButton.tonal(
                      onPressed: loyaltyLoading ? null : onLookupLoyalty,
                      child: loyaltyLoading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                    ),
                  ),
                ],
              ),
              if (loyaltyAccount != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Valeur ${formatMoney(loyaltyAccount!.pointValueEuros)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: _posMuted),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: loyaltyPointsController,
                onChanged: (_) => onChanged(),
                decoration:
                    const InputDecoration(labelText: 'Points a utiliser'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _PaymentSection(
          paymentMethod: paymentMethod,
          canUseTerminal: canUseTerminal,
          externalReferenceController: externalReferenceController,
          amountReceivedController: amountReceivedController,
          total: total,
          change: change,
          amountReceived: amountReceived,
          onChanged: onChanged,
          onPaymentMethodChanged: onPaymentMethodChanged,
        ),
        const SizedBox(height: 10),
        _ExpandableSection(
          title: 'Note cuisine',
          icon: Icons.notes_outlined,
          child: TextField(
            controller: noteController,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(labelText: 'Note'),
            maxLines: 2,
          ),
        ),
        if (!stickyFooter) ...[
          const SizedBox(height: 16),
          _CheckoutFooter(
            total: total,
            submitting: submitting,
            blocked: blocked,
            validationMessage: validationMessage,
            onSubmit: onSubmit,
          ),
        ],
      ],
    );

    return Container(
      color: _posSurface,
      child: Column(
        children: [
          Expanded(child: content),
          if (stickyFooter)
            _CheckoutFooter(
              total: total,
              submitting: submitting,
              blocked: blocked,
              validationMessage: validationMessage,
              onSubmit: onSubmit,
            ),
        ],
      ),
    );
  }
}

class _ContextSection extends StatelessWidget {
  const _ContextSection({
    required this.orderType,
    required this.tableController,
    required this.deliveryAddressController,
    required this.customerEmailController,
    required this.customerNameController,
    required this.customerPhoneController,
    required this.onChanged,
  });

  final String orderType;
  final TextEditingController tableController;
  final TextEditingController deliveryAddressController;
  final TextEditingController customerEmailController;
  final TextEditingController customerNameController;
  final TextEditingController customerPhoneController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _PanelBlock(
      title: 'Contexte',
      child: Column(
        children: [
          if (orderType == 'dine_in') ...[
            TextField(
              controller: tableController,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Table',
                prefixIcon: Icon(Icons.table_restaurant_outlined),
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: customerNameController,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              labelText: 'Nom client',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          if (orderType == 'pickup' || orderType == 'delivery') ...[
            const SizedBox(height: 8),
            TextField(
              controller: customerPhoneController,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: orderType == 'delivery'
                    ? 'Telephone'
                    : 'Telephone optionnel',
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
            ),
          ],
          if (orderType == 'delivery') ...[
            const SizedBox(height: 8),
            TextField(
              controller: deliveryAddressController,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Adresse de livraison',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
          ],
          if (orderType != 'dine_in') ...[
            const SizedBox(height: 8),
            TextField(
              controller: customerEmailController,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Email secondaire',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ],
      ),
    );
  }
}

class _CartLinesSection extends StatelessWidget {
  const _CartLinesSection({
    required this.lines,
    required this.onRemove,
    required this.onIncrement,
    required this.onDecrement,
  });

  final List<CheckoutCartLine> lines;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onIncrement;
  final ValueChanged<String> onDecrement;

  @override
  Widget build(BuildContext context) {
    return _PanelBlock(
      title: 'Panier',
      child: lines.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 34,
                    color: _posMuted,
                  ),
                  SizedBox(height: 8),
                  Text('Votre commande est vide'),
                  Text('Touchez un produit pour l ajouter.'),
                ],
              ),
            )
          : Column(
              children: [
                for (final line in lines) ...[
                  _CartLineTile(
                    line: line,
                    onRemove: () => onRemove(line.key),
                    onIncrement: () => onIncrement(line.key),
                    onDecrement: () => onDecrement(line.key),
                  ),
                  if (line != lines.last) const Divider(height: 16),
                ],
              ],
            ),
    );
  }
}

class _PaymentSection extends StatelessWidget {
  const _PaymentSection({
    required this.paymentMethod,
    required this.canUseTerminal,
    required this.externalReferenceController,
    required this.amountReceivedController,
    required this.total,
    required this.change,
    required this.amountReceived,
    required this.onChanged,
    required this.onPaymentMethodChanged,
  });

  final String paymentMethod;
  final bool canUseTerminal;
  final TextEditingController externalReferenceController;
  final TextEditingController amountReceivedController;
  final double total;
  final double? change;
  final double? amountReceived;
  final VoidCallback onChanged;
  final ValueChanged<String> onPaymentMethodChanged;

  @override
  Widget build(BuildContext context) {
    return _PanelBlock(
      title: 'Paiement',
      child: Column(
        children: [
          _PaymentPads(
            value: paymentMethod,
            canUseTerminal: canUseTerminal,
            onChanged: onPaymentMethodChanged,
          ),
          if ({'external_terminal', 'cash_register'}.contains(paymentMethod))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: externalReferenceController,
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(
                  labelText: 'Reference externe',
                  prefixIcon: Icon(Icons.tag_outlined),
                ),
              ),
            ),
          if (paymentMethod == 'cash') ...[
            const SizedBox(height: 10),
            TextField(
              controller: amountReceivedController,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Montant recu',
                prefixIcon: Icon(Icons.euro_outlined),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _posBackground,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                children: [
                  _AmountRow('Total estime', formatMoney(total)),
                  _AmountRow(
                    'Montant recu',
                    amountReceived == null ? '-' : formatMoney(amountReceived!),
                  ),
                  _AmountRow(
                    'A rendre',
                    change == null
                        ? '-'
                        : formatMoney(change! < 0 ? 0 : change!),
                    strong: true,
                    warning: change != null && change! < 0,
                  ),
                  if (change != null && change! < 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Montant insuffisant',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.danger),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckoutFooter extends StatelessWidget {
  const _CheckoutFooter({
    required this.total,
    required this.submitting,
    required this.blocked,
    required this.validationMessage,
    required this.onSubmit,
  });

  final double total;
  final bool submitting;
  final bool blocked;
  final String? validationMessage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: _posSurfaceRaised,
        border: Border(top: BorderSide(color: _posLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'TOTAL ESTIME',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: _posMuted, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                formatMoney(total),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900, color: _posInk),
              ),
            ],
          ),
          if (validationMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              validationMessage!,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: blocked ? null : onSubmit,
              icon: submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                submitting
                    ? 'Encaissement...'
                    : 'Encaisser ${formatMoney(total)}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderTypeSelector extends StatelessWidget {
  const _OrderTypeSelector({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ModePad(
          label: 'A emporter',
          icon: Icons.shopping_bag_outlined,
          selected: value == 'pickup',
          onTap: () => onChanged('pickup'),
        ),
        const SizedBox(width: 8),
        _ModePad(
          label: 'Sur place',
          icon: Icons.table_restaurant_outlined,
          selected: value == 'dine_in',
          onTap: () => onChanged('dine_in'),
        ),
        const SizedBox(width: 8),
        _ModePad(
          label: 'Livraison',
          icon: Icons.delivery_dining_outlined,
          selected: value == 'delivery',
          onTap: () => onChanged('delivery'),
        ),
      ],
    );
  }
}

class _PaymentPads extends StatelessWidget {
  const _PaymentPads({
    required this.value,
    required this.canUseTerminal,
    required this.onChanged,
  });

  final String value;
  final bool canUseTerminal;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ModePad(
          label: 'Especes',
          icon: Icons.payments_outlined,
          selected: value == 'cash',
          onTap: () => onChanged('cash'),
        ),
        _ModePad(
          label: 'TPE',
          icon: Icons.credit_card_outlined,
          selected: value == 'external_terminal',
          disabled: !canUseTerminal,
          onTap: () => onChanged('external_terminal'),
        ),
        _ModePad(
          label: 'Caisse',
          icon: Icons.point_of_sale_outlined,
          selected: value == 'cash_register',
          onTap: () => onChanged('cash_register'),
        ),
      ],
    );
  }
}

class _ModePad extends StatelessWidget {
  const _ModePad({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : _posInk;
    final fill = selected ? AppColors.adminSidebar : _posSurfaceRaised;
    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: label,
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: DsCard(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          backgroundColor: fill,
          borderColor: selected ? AppColors.adminSidebar : _posLine,
          borderRadius: AppRadius.md,
          onTap: disabled ? null : onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.onRemove,
    required this.onIncrement,
    required this.onDecrement,
  });

  final CheckoutCartLine line;
  final VoidCallback onRemove;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (line.variant != null) line.variant!.name,
      ...line.extras.map((extra) => '+ ${extra.name}'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line.quantity} x ${line.product.name}',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                if (details.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      details.join('\n'),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: _posMuted),
                    ),
                  ),
                const SizedBox(height: 5),
                Text(
                  formatMoney(line.total),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Row(
                children: [
                  _QtyButton(icon: Icons.remove, onTap: onDecrement),
                  SizedBox(
                    width: 38,
                    child: Text(
                      line.quantity.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  _QtyButton(icon: Icons.add, onTap: onIncrement),
                ],
              ),
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Retirer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 42,
      child: FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(padding: EdgeInsets.zero),
        child: Icon(icon),
      ),
    );
  }
}

class _ExpandableSection extends StatefulWidget {
  const _ExpandableSection({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return _PanelBlock(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: Icon(widget.icon),
              title: Text(
                widget.title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
              trailing: Icon(_open ? Icons.expand_less : Icons.expand_more),
              onTap: () => setState(() => _open = !_open),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: widget.child,
            ),
            crossFadeState:
                _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 160),
          ),
        ],
      ),
    );
  }
}

class _PanelBlock extends StatelessWidget {
  const _PanelBlock({
    required this.child,
    this.title,
    this.padding = const EdgeInsets.all(14),
  });

  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _posSurfaceRaised,
        border: Border.all(color: _posLine),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            _SectionLabel(title!),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

class _ChoicePad extends StatelessWidget {
  const _ChoicePad({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : _posInk;
    final fill = selected ? AppColors.adminSidebar : _posSurfaceRaised;
    return SizedBox(
      width: 156,
      child: DsCard(
        padding: const EdgeInsets.all(12),
        backgroundColor: fill,
        borderColor: selected ? AppColors.adminSidebar : _posLine,
        borderRadius: AppRadius.md,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: foreground,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _ModePad(
        label: label,
        icon: selected ? Icons.check : Icons.label_outline,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

class _MobileCartBar extends StatelessWidget {
  const _MobileCartBar({
    required this.itemCount,
    required this.total,
    required this.onOpen,
  });

  final int itemCount;
  final double total;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.all(12),
      backgroundColor: AppColors.adminSidebar,
      borderColor: AppColors.adminSidebar,
      borderRadius: AppRadius.lg,
      onTap: onOpen,
      child: Row(
        children: [
          const Icon(Icons.shopping_cart_outlined, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$itemCount article(s) - ${formatMoney(total)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          FilledButton(
            onPressed: onOpen,
            child: const Text('Voir panier'),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warningSoftBg,
          border: Border.all(color: AppColors.warning),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _SuccessRow extends StatelessWidget {
  const _SuccessRow({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(
    this.label,
    this.value, {
    this.strong = false,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool strong;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              color: warning ? AppColors.danger : _posInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: _posMuted,
            fontWeight: FontWeight.w900,
          ),
    );
  }
}

class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 230,
          mainAxisExtent: 132,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 12,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: _posSurfaceRaised.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: _posLine),
          ),
        ),
      ),
    );
  }
}

double? _parsePanelAmount(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return null;
  }
  return double.tryParse(normalized);
}

String _paymentLabel(String value) {
  return switch (value) {
    'external_terminal' => 'TPE',
    'cash_register' => 'Caisse externe',
    'cash' => 'Especes',
    _ => value,
  };
}
