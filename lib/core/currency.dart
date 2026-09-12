/// Una divisa soportada por la app.
///
/// La app solo maneja divisas de dos decimales. Si algún día entra una de
/// cero decimales (JPY) o tres (KWD), [decimalDigits] ya está preparado.
class Currency {
  final String code;
  final String symbol;
  final int decimalDigits;

  /// Privado a propósito: el conjunto de divisas es cerrado. Si cualquiera
  /// pudiera construir una, `Currency('EUR', 'X', 0)` sería `==` a
  /// [Currency.eur] —porque la igualdad va por código— y se colaría hasta el
  /// formateo, imprimiendo «123456 €» en lugar de «1.234,56 €».
  const Currency._(this.code, this.symbol, this.decimalDigits);

  static const eur = Currency._('EUR', '€', 2);
  static const gbp = Currency._('GBP', '£', 2);
  static const usd = Currency._('USD', r'$', 2);

  static const all = <Currency>[eur, gbp, usd];

  static Currency byCode(String code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    throw ArgumentError('Divisa no soportada: $code');
  }

  /// 10^decimalDigits — cuántas unidades menores tiene una unidad.
  int get minorUnitsPerUnit {
    var n = 1;
    for (var i = 0; i < decimalDigits; i++) {
      n *= 10;
    }
    return n;
  }

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}
