import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/fx.dart';
import 'package:finanzas/core/money.dart';

void main() {
  test('el euro consigo mismo vale uno', () {
    expect(FxRate.identity(Currency.eur).scaled, FxRate.scale);
  });

  test('convierte libras a euros', () {
    // 1 GBP = 1,17234500 EUR
    const rate = FxRate(Currency.gbp, 117234500);
    final eur = rate.toEur(const Money(2450, Currency.gbp));
    // 2450 * 1,172345 = 2872,245... céntimos -> 2872
    expect(eur, const Money(2872, Currency.eur));
  });

  test('redondea el medio hacia arriba', () {
    // 1 X = 1,005 EUR sobre 100 céntimos -> 100,5 -> 101
    const rate = FxRate(Currency.usd, 100500000);
    expect(rate.toEur(const Money(100, Currency.usd)).minorUnits, 101);
  });

  test('convertir cero da cero', () {
    const rate = FxRate(Currency.gbp, 117234500);
    expect(rate.toEur(const Money(0, Currency.gbp)).minorUnits, 0);
  });

  test('en negativo el medio se aleja de cero', () {
    // Mismo empate exacto que la prueba anterior, con signo: -100,5 -> -101.
    // Una deuda nunca se redondea a una cifra menor de la que es.
    const rate = FxRate(Currency.usd, 100500000);
    expect(rate.toEur(const Money(-100, Currency.usd)).minorUnits, -101);
  });

  test('convertir una divisa que no es la del tipo es un error', () {
    const rate = FxRate(Currency.gbp, 117234500);
    expect(
      () => rate.toEur(const Money(100, Currency.usd)),
      throwsA(isA<CurrencyMismatchError>()),
    );
  });

  test('construye el tipo a euros desde la cotización del BCE', () {
    // El BCE publica «cuántas libras vale un euro». Nosotros guardamos lo
    // contrario: cuántos euros vale una libra.
    final rate = FxRate.fromEcbQuote(Currency.gbp, 0.85300);
    expect(rate.scaled, closeTo(117233294, 2));
  });
}
