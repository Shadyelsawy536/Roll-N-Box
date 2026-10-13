import 'package:intl/intl.dart';

/// Formats monetary values with thousands separators and two decimal places.
String formatMoney(num value) => NumberFormat('#,##0.00', 'en_US').format(value);
