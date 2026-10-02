import 'currency.dart';

/// Se ha intentado operar con dos divisas distintas.
class CurrencyMismatchError extends Error {
  final Currency a;
  final Currency b;
  CurrencyMismatchError(this.a, this.b);

  @override
  String toString() => 'No se pueden mezclar $a y $b en la misma operación';
}

/// Un importe de dinero.
///
/// Se guarda siempre en unidades menores (céntimos) como entero. Nunca en
/// coma flotante: `0.1 + 0.2 != 0.3`, y en finanzas eso son saldos que dejan
/// de cuadrar.
class Money implements Comparable<Money> {
  final int minorUnits;
  final Currency currency;

  const Money(this.minorUnits, this.currency);

  /// Atajo para pruebas. **No sirve para importar datos reales.**
  ///
  /// Pasa por coma flotante, así que hereda sus errores: `1.005` se almacena
  /// como `1.00499999...` y esto devuelve 100 céntimos, no 101. Para dos
  /// decimales exactos (`24.50`, `19.99`) es seguro, porque el error queda
  /// órdenes de magnitud por debajo del medio céntimo.
  ///
  /// La importación de CSV **no debe usar esto**: tiene que parsear la cadena
  /// decimal a entero directamente, sin pasar por `double`.
  factory Money.fromUnits(double units, Currency currency) =>
      Money((units * currency.minorUnitsPerUnit).round(), currency);

  static Money zero(Currency currency) => Money(0, currency);

  /// Suma acumulando con `+`, que es quien comprueba la divisa. Hacerlo con
  /// un entero suelto y un control propio duplicaría esa comprobación, y la
  /// copia duplicada no la ejercita ninguna prueba.
  static Money sum(Iterable<Money> items, Currency currency) {
    var total = zero(currency);
    for (final m in items) {
      total += m;
    }
    return total;
  }

  Money operator +(Money other) =>
      Money(minorUnits + _same(other).minorUnits, currency);

  Money operator -(Money other) =>
      Money(minorUnits - _same(other).minorUnits, currency);

  Money operator -() => Money(-minorUnits, currency);

  bool operator >(Money other) => minorUnits > _same(other).minorUnits;
  bool operator <(Money other) => minorUnits < _same(other).minorUnits;

  bool get isNegative => minorUnits < 0;
  bool get isZero => minorUnits == 0;

  Money get abs => Money(minorUnits.abs(), currency);

  Money _same(Money other) {
    if (other.currency != currency) throw CurrencyMismatchError(currency, other.currency);
    return other;
  }

  @override
  int compareTo(Money other) => minorUnits.compareTo(_same(other).minorUnits);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minorUnits == minorUnits && other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => '$minorUnits ${currency.code}';
}
