import 'package:intl/intl.dart';
import 'money.dart';

/// «1.234,56 €». La división por 100 es exacta en coma flotante para
/// cualquier cifra realista y solo se usa para presentar, nunca para calcular.
///
/// El menos de `intl` es un guion ASCII; aquí se cambia por el menos
/// tipográfico (−, U+2212) para que un saldo negativo se vea igual venga de
/// aquí o de [formatSigned]. Si no, en la misma pantalla conviven dos signos
/// menos distintos: el de la lista de movimientos y el del saldo de arriba.
String formatMoney(Money m, {String locale = 'es_ES'}) {
  final formatter = NumberFormat.currency(
    locale: locale,
    symbol: m.currency.symbol,
    decimalDigits: m.currency.decimalDigits,
  );
  return formatter
      .format(m.minorUnits / m.currency.minorUnitsPerUnit)
      .replaceFirst('-', '\u2212');
}

/// Con signo explícito, para las listas de movimientos. Usa el menos
/// tipográfico (−, U+2212), que se alinea con los dígitos.
String formatSigned(Money m, {required bool negate, String locale = 'es_ES'}) {
  final body = formatMoney(m.abs, locale: locale);
  return negate ? '−$body' : '+$body';
}
