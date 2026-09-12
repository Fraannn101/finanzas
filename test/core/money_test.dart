import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/money.dart';

void main() {
  test('guarda el importe en unidades menores', () {
    expect(Money.fromUnits(24.50, Currency.gbp).minorUnits, 2450);
  });

  test('suma y resta importes de la misma divisa', () {
    const a = Money(2450, Currency.gbp);
    const b = Money(550, Currency.gbp);
    expect((a + b).minorUnits, 3000);
    expect((a - b).minorUnits, 1900);
  });

  test('sumar divisas distintas es un error', () {
    const libras = Money(2450, Currency.gbp);
    const euros = Money(2450, Currency.eur);
    expect(() => libras + euros, throwsA(isA<CurrencyMismatchError>()));
  });

  test('compara importes de la misma divisa', () {
    expect(const Money(100, Currency.eur) > const Money(99, Currency.eur), isTrue);
    expect(const Money(-1, Currency.eur).isNegative, isTrue);
  });

  test('dos importes iguales son iguales', () {
    expect(const Money(2450, Currency.gbp), const Money(2450, Currency.gbp));
    expect(const Money(2450, Currency.gbp), isNot(const Money(2450, Currency.eur)));
  });

  test('suma una lista de importes de la misma divisa', () {
    final total = Money.sum(
      [const Money(100, Currency.eur), const Money(250, Currency.eur)],
      Currency.eur,
    );
    expect(total.minorUnits, 350);
  });

  test('la suma de una lista vacía es cero en la divisa dada', () {
    expect(Money.sum(const [], Currency.usd).minorUnits, 0);
  });
}
