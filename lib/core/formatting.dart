import 'package:intl/intl.dart';
import 'money.dart';

/// «1.234,56 €». La división por 100 es exacta en coma flotante para
/// cualquier cifra realista y solo se usa para presentar, nunca para calcular.
String formatMoney(Money m, {String locale = 'es_ES'}) {
  final formatter = NumberFormat.currency(
    locale: locale,
    symbol: m.currency.symbol,
    decimalDigits: m.currency.decimalDigits,
  );
  return formatter.format(m.minorUnits / m.currency.minorUnitsPerUnit);
}

/// Con signo explícito, para las listas de movimientos. Usa el menos
/// tipográfico (−, U+2212), que se alinea con los dígitos.
String formatSigned(Money m, {required bool negate, String locale = 'es_ES'}) {
  final body = formatMoney(m.abs, locale: locale);
  return negate ? '−$body' : '+$body';
}
