import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/formatting.dart';
import 'package:finanzas/core/money.dart';

// intl separa el número del símbolo con un espacio duro, no con un espacio
// normal. Se escribe como escape y no pegando el carácter: invisible en el
// diff, y cualquier editor que normalice espacios lo rompe sin dejar rastro.
const _nbsp = '\u00A0';

void main() {
  test('formatea euros al estilo español', () {
    expect(formatMoney(const Money(123456, Currency.eur)), '1.234,56$_nbsp€');
  });

  test('formatea libras con su símbolo', () {
    expect(formatMoney(const Money(2450, Currency.gbp)), '24,50$_nbsp£');
  });

  test('formatea negativos con el menos tipográfico', () {
    expect(formatMoney(const Money(-31240, Currency.eur)), '−312,40$_nbsp€');
  });

  test('con signo explícito para las listas de movimientos', () {
    expect(formatSigned(const Money(5230, Currency.eur), negate: true), '−52,30$_nbsp€');
    expect(formatSigned(const Money(240000, Currency.usd), negate: false), '+2.400,00$_nbsp\$');
  });
}
