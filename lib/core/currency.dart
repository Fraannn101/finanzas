/// Una divisa soportada por la app.
///
/// La app solo maneja divisas de dos decimales. Si algún día entra una de
/// cero decimales (JPY) o tres (KWD), [decimalDigits] ya está preparado.
class Currency {
  final String code;
  final String symbol;
  final int decimalDigits;

  const Currency(this.code, this.symbol, this.decimalDigits);

  static const eur = Currency('EUR', '€', 2);
  static const gbp = Currency('GBP', '£', 2);
  static const usd = Currency('USD', r'$', 2);

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
