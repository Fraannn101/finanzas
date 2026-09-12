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

  /// Solo para pruebas y para leer de fuentes externas (CSV). El resto de la
  /// app trabaja siempre con unidades menores.
  factory Money.fromUnits(double units, Currency currency) =>
      Money((units * currency.minorUnitsPerUnit).round(), currency);

  static Money zero(Currency currency) => Money(0, currency);

  static Money sum(Iterable<Money> items, Currency currency) {
    var total = 0;
    for (final m in items) {
      if (m.currency != currency) throw CurrencyMismatchError(currency, m.currency);
      total += m.minorUnits;
    }
    return Money(total, currency);
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
