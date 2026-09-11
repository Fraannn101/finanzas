import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';

void main() {
  test('busca una divisa por su código ISO', () {
    expect(Currency.byCode('GBP'), Currency.gbp);
    expect(Currency.byCode('EUR').symbol, '€');
  });

  test('rechaza una divisa no soportada', () {
    expect(() => Currency.byCode('JPY'), throwsArgumentError);
  });

  test('dos instancias del mismo código son iguales', () {
    expect(const Currency('EUR', '€', 2), Currency.eur);
  });
}
