import 'package:intl/intl.dart';

class Formatters {
  static final _currencyFormatter = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 2,
  );

  static final _dateFormatter = DateFormat('MMM d, yyyy');
  static final _shortDateFormatter = DateFormat('M/d/yy');

  static String currency(double? amount) {
    if (amount == null) return '\$0.00';
    return _currencyFormatter.format(amount);
  }

  static String date(DateTime? date) {
    if (date == null) return '';
    return _dateFormatter.format(date);
  }

  static String shortDate(DateTime? date) {
    if (date == null) return '';
    return _shortDateFormatter.format(date);
  }

  static String laborCost(double? hours, double? rate) {
    if (hours == null || rate == null) return '\$0.00';
    return currency(hours * rate);
  }
}
