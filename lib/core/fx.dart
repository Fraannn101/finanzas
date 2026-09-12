import 'currency.dart';
import 'money.dart';

/// Cuántos euros vale una unidad de [currency], escalado ×10⁸.
class FxRate {
  /// 10⁸ — ocho decimales de precisión, entero.
  static const int scale = 100000000;

  final Currency currency;
  final int scaled;

  const FxRate(this.currency, this.scaled);

  factory FxRate.identity(Currency currency) => FxRate(currency, scale);

  /// El BCE publica «unidades de divisa por euro». Invertimos la cotización.
  ///
  /// Se rechaza lo no finito además de lo negativo: `scale / infinity` daría
  /// un tipo de 0 sin quejarse, y un tipo 0 convierte en cero silenciosamente
  /// todos los importes de esa divisa.
  factory FxRate.fromEcbQuote(Currency currency, double unitsPerEuro) {
    if (unitsPerEuro <= 0 || !unitsPerEuro.isFinite) {
      throw ArgumentError('Cotización inválida para $currency: $unitsPerEuro');
    }
    return FxRate(currency, (scale / unitsPerEuro).round());
  }

  Money toEur(Money amount) {
    if (amount.currency != currency) {
      throw CurrencyMismatchError(currency, amount.currency);
    }
    return Money(_divideRoundHalfUp(amount.minorUnits * scaled, scale), Currency.eur);
  }

  /// División entera con el medio redondeado hacia arriba en magnitud.
  static int _divideRoundHalfUp(int numerator, int denominator) {
    final negative = numerator < 0;
    final n = numerator.abs();
    final quotient = n ~/ denominator;
    final remainder = n % denominator;
    final rounded = (remainder * 2 >= denominator) ? quotient + 1 : quotient;
    return negative ? -rounded : rounded;
  }

  @override
  String toString() => '1 ${currency.code} = ${scaled / scale} EUR';
}
