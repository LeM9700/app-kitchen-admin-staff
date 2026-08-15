import 'package:app_admin_staff/design_system/states/order_status_ui.dart';
import 'package:intl/intl.dart';

final _moneyFormat = NumberFormat.currency(locale: 'fr_FR', symbol: 'EUR');
final _timeFormat = DateFormat('HH:mm');
final _dateTimeFormat = DateFormat('dd/MM HH:mm');

String formatMoney(double value) => _moneyFormat.format(value);

String formatCents(int cents) => formatMoney(cents / 100);

String formatTime(DateTime? value) {
  if (value == null) {
    return '-';
  }
  return _timeFormat.format(value.toLocal());
}

String formatDateTime(DateTime? value) {
  if (value == null) {
    return '-';
  }
  return _dateTimeFormat.format(value.toLocal());
}

String humanOrderType(String value) {
  return switch (value) {
    'delivery' => 'Livraison',
    'pickup' => 'Emporter',
    'dine_in' => 'Sur place',
    _ => value,
  };
}

String humanStatus(String value) {
  return OrderStatusUi.from(value).label;
}
