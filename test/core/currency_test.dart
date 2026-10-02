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

  test('divisas distintas no son iguales', () {
    expect(Currency.eur, isNot(Currency.gbp));
  });

  test('buscar por código devuelve la instancia canónica', () {
    expect(identical(Currency.byCode('EUR'), Currency.eur), isTrue);
  });

  test('calcula las unidades menores por unidad', () {
    expect(Currency.eur.minorUnitsPerUnit, 100);
  });

  test('se imprime como su código', () {
    expect(Currency.gbp.toString(), 'GBP');
  });
}
