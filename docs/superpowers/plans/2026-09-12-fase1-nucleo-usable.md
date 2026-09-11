# Fase 1 · Núcleo usable — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Una app Android capaz de registrar gastos, ingresos y transferencias en cuentas de distintas divisas (EUR/GBP/USD), con conversión automática a euros y patrimonio total correcto.

**Architecture:** Cuatro capas — pantallas Flutter → controladores Riverpod → repositorios (donde viven las reglas del dinero) → Drift/SQLite local. El dinero se maneja siempre como enteros de unidades menores dentro de un objeto `Money` que lleva la divisa consigo, de modo que sumar libras con euros no compila.

**Tech Stack:** Flutter 3.41 · Drift sobre SQLite · Riverpod · intl · API pública de tipos de cambio del BCE.

**Spec:** `docs/superpowers/specs/2026-09-12-app-finanzas-personales-design.md`

---

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `lib/core/currency.dart` | Las tres divisas soportadas y sus símbolos |
| `lib/core/money.dart` | Importe + divisa como un solo valor; aritmética segura |
| `lib/core/fx.dart` | Un tipo de cambio y la conversión a euros con su redondeo |
| `lib/core/formatting.dart` | De `Money` a texto legible («1.234,56 €») |
| `lib/core/civil_date.dart` | Fechas sin hora, en texto `YYYY-MM-DD` |
| `lib/data/db/tables.dart` | Definición de tablas y enumeraciones |
| `lib/data/db/database.dart` | Apertura, versión de esquema, migraciones, semilla |
| `lib/data/repositories/account_repository.dart` | Cuentas, instituciones y saldos calculados |
| `lib/data/repositories/category_repository.dart` | Categorías |
| `lib/data/repositories/fx_repository.dart` | Almacén de tipos de cambio |
| `lib/data/repositories/transaction_repository.dart` | Alta, edición y borrado de movimientos |
| `lib/data/services/ecb_fx_service.dart` | Descarga y parseo del XML del BCE |
| `lib/app/providers.dart` | Cableado de Riverpod |
| `lib/app/app.dart` | Tema y navegación |
| `lib/features/home/home_screen.dart` | Lista del mes + patrimonio |
| `lib/features/transactions/add_sheet.dart` | La hoja de añadir |
| `lib/features/transactions/edit_screen.dart` | Edición de un movimiento |
| `lib/features/accounts/accounts_screen.dart` | Cuentas agrupadas por institución |

Cada archivo tiene una responsabilidad. Los de `core/` no importan nada de `data/`; los de `data/` no importan nada de `features/`. Esa dirección única es lo que permite probar el dinero sin emulador.

---

## Task 1: Crear el proyecto Flutter dentro del repositorio

**Files:**
- Create: `pubspec.yaml`, `lib/main.dart`, `android/`, `ios/`, `test/`
- Modify: `.gitignore`

- [ ] **Step 1: Generar el proyecto en el directorio actual**

El repositorio ya existe y contiene `docs/`. `flutter create` respeta lo que ya hay.

```bash
cd "C:/Users/Admin/Documents/Claude/Projects/Improvements"
flutter create --project-name finanzas --org com.elrockmola --platforms android,ios .
```

- [ ] **Step 2: Restaurar `.gitignore`**

`flutter create` sobrescribe `.gitignore`. Comprueba que sigue ignorando el directorio del compañero visual y vuelve a añadirlo si no:

```bash
grep -q '^\.superpowers/$' .gitignore || printf '\n.superpowers/\n' >> .gitignore
grep -c 'superpowers' .gitignore
```

Expected: imprime `1` o más.

- [ ] **Step 3: Verificar que el andamiaje compila y pasa sus pruebas**

```bash
flutter test
```

Expected: `All tests passed!` (la prueba de ejemplo que genera Flutter).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: scaffold Flutter project for Android and iOS"
```

---

## Task 2: Añadir las dependencias

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Instalar dependencias de ejecución y de desarrollo**

```bash
flutter pub add drift:2.34.0 drift_flutter path_provider flutter_riverpod intl http
flutter pub add --dev drift_dev:2.34.0 build_runner
```

**Por qué `drift` va clavado a 2.34.0 y no con `^`:** `drift` y `drift_dev` 2.35.0 exigen `analyzer >=13`, que a su vez exige `meta >=1.18`. Flutter 3.41.4 trae `meta 1.17.0` clavado en el SDK, así que 2.35.0 no resuelve de ninguna manera. La pareja 2.34.0 sí, con `analyzer 10.0.1`. Las dos versiones tienen que moverse juntas: `drift_dev` genera el código que consume `drift`, y un desajuste entre ellas da errores de compilación difíciles de leer. De ahí el pin exacto en ambas, sin intercalo.

Cuando Flutter suba su `meta` a 1.18 o superior, se podrá pasar a `^2.35.0` en ambas a la vez y regenerar con `build_runner`.

- [ ] **Step 2: Verificar que resuelve**

```bash
flutter pub get
```

Expected: `Got dependencies!` sin conflictos.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add drift, riverpod, intl and http dependencies"
```

---

## Task 3: Las divisas soportadas

**Files:**
- Create: `lib/core/currency.dart`
- Test: `test/core/currency_test.dart`

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/core/currency_test.dart
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
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/core/currency_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'finanzas'` o `currency.dart not found`.

- [ ] **Step 3: Implementar lo mínimo**

```dart
// lib/core/currency.dart

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
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/core/currency_test.dart`
Expected: PASS, 3 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/core/currency.dart test/core/currency_test.dart
git commit -m "feat: add Currency value object for EUR, GBP and USD"
```

---

## Task 4: `Money` — importe y divisa inseparables

**Files:**
- Create: `lib/core/money.dart`
- Test: `test/core/money_test.dart`

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/core/money_test.dart
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
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/core/money_test.dart`
Expected: FAIL — `money.dart not found`.

- [ ] **Step 3: Implementar lo mínimo**

```dart
// lib/core/money.dart
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
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/core/money_test.dart`
Expected: PASS, 7 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/core/money.dart test/core/money_test.dart
git commit -m "feat: add Money value object with currency-safe arithmetic"
```

---

## Task 5: Conversión a euros y su redondeo

**Files:**
- Create: `lib/core/fx.dart`
- Test: `test/core/fx_test.dart`

Los tipos se guardan escalados ×10⁸ (`1 GBP = 1,17234500 EUR` → `117234500`), enteros, por la misma razón que los importes.

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/core/fx_test.dart
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
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/core/fx_test.dart`
Expected: FAIL — `fx.dart not found`.

- [ ] **Step 3: Implementar lo mínimo**

```dart
// lib/core/fx.dart
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
  factory FxRate.fromEcbQuote(Currency currency, double unitsPerEuro) {
    if (unitsPerEuro <= 0) {
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
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/core/fx_test.dart`
Expected: PASS, 6 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/core/fx.dart test/core/fx_test.dart
git commit -m "feat: add FxRate with integer-scaled EUR conversion"
```

---

## Task 6: Fechas sin hora

**Files:**
- Create: `lib/core/civil_date.dart`
- Test: `test/core/civil_date_test.dart`

Un gasto de las 23:50 no debe saltar de día por un cambio de huso horario. Las fechas de los movimientos se guardan como texto `YYYY-MM-DD`, que además ordena correctamente en SQL.

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/core/civil_date_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/civil_date.dart';

void main() {
  test('convierte una fecha a texto ISO sin hora', () {
    expect(civilDateOf(DateTime(2026, 9, 12, 23, 50)), '2026-09-12');
  });

  test('rellena con ceros meses y días de una cifra', () {
    expect(civilDateOf(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('vuelve a DateTime a medianoche local', () {
    final d = parseCivilDate('2026-09-12');
    expect(d.year, 2026);
    expect(d.month, 9);
    expect(d.day, 12);
    expect(d.hour, 0);
  });

  test('el primer y el último día del mes', () {
    expect(firstDayOfMonth(DateTime(2026, 9, 12)), '2026-09-01');
    expect(lastDayOfMonth(DateTime(2026, 2, 5)), '2026-02-28');
  });
}
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/core/civil_date_test.dart`
Expected: FAIL — `civil_date.dart not found`.

- [ ] **Step 3: Implementar lo mínimo**

```dart
// lib/core/civil_date.dart

/// Una fecha sin hora, como texto `YYYY-MM-DD`.
///
/// Se guarda en texto y no como marca de tiempo para que ningún cambio de
/// huso horario mueva un movimiento de día. Además ordena bien en SQL.
String civilDateOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseCivilDate(String iso) {
  final parts = iso.split('-');
  if (parts.length != 3) throw FormatException('Fecha inválida: $iso');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

String todayCivil() => civilDateOf(DateTime.now());

String firstDayOfMonth(DateTime d) => civilDateOf(DateTime(d.year, d.month, 1));

/// Día 0 del mes siguiente = último día de este mes. Resuelve febrero solo.
String lastDayOfMonth(DateTime d) => civilDateOf(DateTime(d.year, d.month + 1, 0));
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/core/civil_date_test.dart`
Expected: PASS, 4 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/core/civil_date.dart test/core/civil_date_test.dart
git commit -m "feat: add timezone-safe civil date helpers"
```

---

## Task 7: Formato de importes

**Files:**
- Create: `lib/core/formatting.dart`
- Test: `test/core/formatting_test.dart`

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/core/formatting_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/formatting.dart';
import 'package:finanzas/core/money.dart';

void main() {
  test('formatea euros al estilo español', () {
    expect(formatMoney(const Money(123456, Currency.eur)), '1.234,56 €');
  });

  test('formatea libras con su símbolo', () {
    expect(formatMoney(const Money(2450, Currency.gbp)), '24,50 £');
  });

  test('formatea negativos con el signo delante', () {
    expect(formatMoney(const Money(-31240, Currency.eur)), '-312,40 €');
  });

  test('con signo explícito para las listas de movimientos', () {
    expect(formatSigned(const Money(5230, Currency.eur), negate: true), '−52,30 €');
    expect(formatSigned(const Money(240000, Currency.usd), negate: false), r'+2.400,00 $');
  });
}
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/core/formatting_test.dart`
Expected: FAIL — `formatting.dart not found`.

- [ ] **Step 3: Implementar lo mínimo**

```dart
// lib/core/formatting.dart
import 'package:intl/intl.dart';
import 'money.dart';

/// «1.234,56 €». La división por 100 es exacta en coma flotante para
/// cualquier cifra realista y solo se usa para presentar, nunca para calcular.
String formatMoney(Money m, {String locale = 'es_ES'}) {
  final formatter = NumberFormat.currency(
    locale: locale,
    symbol: m.currency.symbol,
    decimalDigits: m.currency.decimalDigits,
  );
  return formatter.format(m.minorUnits / m.currency.minorUnitsPerUnit);
}

/// Con signo explícito, para las listas de movimientos. Usa el menos
/// tipográfico (−, U+2212), que se alinea con los dígitos.
String formatSigned(Money m, {required bool negate, String locale = 'es_ES'}) {
  final body = formatMoney(m.abs, locale: locale);
  return negate ? '−$body' : '+$body';
}
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/core/formatting_test.dart`
Expected: PASS, 4 pruebas.

Si el formato de euros falla por el espacio entre número y símbolo, imprime el valor real con `print(formatMoney(...))` y ajusta la cadena esperada: `intl` usa un espacio duro (U+00A0), no un espacio normal. Corrige la **prueba**, no el código.

- [ ] **Step 5: Commit**

```bash
git add lib/core/formatting.dart test/core/formatting_test.dart
git commit -m "feat: add money formatting for Spanish locale"
```

---

## Task 8: Las tablas

**Files:**
- Create: `lib/data/db/tables.dart`

- [ ] **Step 1: Escribir las definiciones**

```dart
// lib/data/db/tables.dart
import 'package:drift/drift.dart';

enum AccountType { cash, checking, savings, creditCard }

enum CategoryKind { expense, income }

enum TxType { expense, income, transfer }

/// Agrupación visual: Revolut, BBVA, Barclays.
class Institutions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get icon => text().withDefault(const Constant('🏦'))();
  TextColumn get color => text().withDefault(const Constant('#6B7280'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// Una cuenta tiene una divisa y solo una. Revolut son tres cuentas.
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get institutionId =>
      integer().nullable().references(Institutions, #id)();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  TextColumn get type => textEnum<AccountType>()();
  IntColumn get initialBalanceMinor => integer().withDefault(const Constant(0))();
  IntColumn get creditLimitMinor => integer().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get icon => text().withDefault(const Constant('🏷️'))();
  TextColumn get color => text().withDefault(const Constant('#6B7280'))();
  TextColumn get kind => textEnum<CategoryKind>()();
  IntColumn get parentId => integer().nullable().references(Categories, #id)();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// `Txn` y no `Transaction` para no chocar con la clase homónima de Drift.
@DataClassName('Txn')
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<TxType>()();
  IntColumn get accountId => integer().references(Accounts, #id)();

  /// Siempre positivo. El signo lo determina [type].
  IntColumn get amountMinor => integer()();

  /// Copiada de la cuenta en el momento del alta, para que el histórico no
  /// cambie si alguien toca la cuenta después.
  TextColumn get currency => text().withLength(min: 3, max: 3)();

  /// Congelado el día del movimiento. Escalado ×10⁸.
  IntColumn get fxRateToEurScaled => integer()();
  IntColumn get amountEurMinor => integer()();

  /// Cierto si se usó un tipo de otro día por no haber conexión.
  BoolColumn get fxIsEstimated => boolean().withDefault(const Constant(false))();

  /// `YYYY-MM-DD`, sin hora.
  TextColumn get date => text().withLength(min: 10, max: 10)();

  IntColumn get categoryId => integer().nullable().references(Categories, #id)();

  /// Solo en transferencias: cuenta destino e importe recibido en su divisa.
  IntColumn get counterAccountId =>
      integer().nullable().references(Accounts, #id)();
  IntColumn get counterAmountMinor => integer().nullable()();

  TextColumn get merchant => text().nullable()();
  TextColumn get note => text().nullable()();

  /// Reservados para las fases siguientes del plan.
  IntColumn get recurringRuleId => integer().nullable()();
  IntColumn get importBatchId => integer().nullable()();
  TextColumn get dedupeHash => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// `FxRateRow` para no chocar con `FxRate` de `core/fx.dart`.
@DataClassName('FxRateRow')
class FxRates extends Table {
  TextColumn get date => text().withLength(min: 10, max: 10)();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  IntColumn get rateToEurScaled => integer()();
  TextColumn get source => text()(); // 'ecb' | 'manual'

  @override
  Set<Column> get primaryKey => {date, currency};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/data/db/tables.dart
git commit -m "feat: define database tables for accounts, transactions and FX"
```

---

## Task 9: La base de datos y su semilla

**Files:**
- Create: `lib/data/db/database.dart`
- Test: `test/data/database_test.dart`

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/data/database_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/db/tables.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('crea el esquema en la versión 1', () async {
    expect(db.schemaVersion, 1);
    await db.accounts.select().get(); // no lanza
  });

  test('siembra categorías de gasto y de ingreso', () async {
    final all = await db.categories.select().get();
    expect(all.where((c) => c.kind == CategoryKind.expense), isNotEmpty);
    expect(all.where((c) => c.kind == CategoryKind.income), isNotEmpty);
  });

  test('aplica las claves foráneas', () async {
    expect(
      () => db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              type: TxType.expense,
              accountId: 999, // no existe
              amountMinor: 100,
              currency: 'EUR',
              fxRateToEurScaled: 100000000,
              amountEurMinor: 100,
              date: '2026-09-12',
            ),
          ),
      throwsA(anything),
    );
  });
}
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/data/database_test.dart`
Expected: FAIL — `database.dart not found`.

- [ ] **Step 3: Escribir la base de datos**

```dart
// lib/data/db/database.dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Institutions, Accounts, Categories, Transactions, FxRates, AppSettings],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'finanzas'));

  /// Base en memoria, para las pruebas.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedCategories();
        },
        beforeOpen: (details) async {
          // Sin esto SQLite ignora las claves foráneas en silencio.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _seedCategories() async {
    const expenses = <(String, String)>[
      ('Súper', '🛒'),
      ('Restaurantes', '🍽️'),
      ('Casa', '🏠'),
      ('Transporte', '⛽'),
      ('Salud', '💊'),
      ('Ocio', '🎬'),
      ('Compras', '🛍️'),
      ('Suscripciones', '🔁'),
      ('Otros', '📦'),
    ];
    const incomes = <(String, String)>[
      ('Nómina', '💼'),
      ('Freelance', '🧾'),
      ('Regalos', '🎁'),
      ('Otros ingresos', '📥'),
    ];

    var order = 0;
    for (final (name, icon) in expenses) {
      await into(categories).insert(CategoriesCompanion.insert(
        name: name,
        kind: CategoryKind.expense,
        icon: Value(icon),
        sortOrder: Value(order++),
      ));
    }
    order = 0;
    for (final (name, icon) in incomes) {
      await into(categories).insert(CategoriesCompanion.insert(
        name: name,
        kind: CategoryKind.income,
        icon: Value(icon),
        sortOrder: Value(order++),
      ));
    }
  }
}
```

- [ ] **Step 4: Generar el código de Drift**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: `Succeeded after ...` y aparece `lib/data/db/database.g.dart`.

- [ ] **Step 5: Ejecutar la prueba para verla pasar**

Run: `flutter test test/data/database_test.dart`
Expected: PASS, 3 pruebas.

- [ ] **Step 6: Commit**

```bash
git add lib/data/db/ test/data/database_test.dart
git commit -m "feat: add app database with schema v1 and default categories"
```

---

## Task 10: Repositorio de cuentas

**Files:**
- Create: `lib/data/repositories/account_repository.dart`
- Test: `test/data/account_repository_test.dart`

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/data/account_repository_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/db/tables.dart';
import 'package:finanzas/data/repositories/account_repository.dart';

void main() {
  late AppDatabase db;
  late AccountRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AccountRepository(db);
  });
  tearDown(() => db.close());

  test('crea una cuenta con saldo inicial', () async {
    final id = await repo.create(
      name: 'Libras',
      currency: Currency.gbp,
      type: AccountType.checking,
      initialBalanceMinor: 42810,
    );
    final account = await repo.byId(id);
    expect(account.name, 'Libras');
    expect(account.currency, 'GBP');
  });

  test('agrupa las cuentas por institución', () async {
    final revolut = await repo.createInstitution(name: 'Revolut', icon: '💳');
    await repo.create(
      name: 'Libras',
      currency: Currency.gbp,
      type: AccountType.checking,
      institutionId: revolut,
    );
    await repo.create(
      name: 'Euros',
      currency: Currency.eur,
      type: AccountType.checking,
      institutionId: revolut,
    );
    await repo.create(
      name: 'Efectivo',
      currency: Currency.eur,
      type: AccountType.cash,
    );

    final groups = await repo.groupedByInstitution();
    expect(groups.length, 2); // Revolut y el grupo sin institución
    expect(groups.first.institution?.name, 'Revolut');
    expect(groups.first.accounts.length, 2);
    expect(groups.last.institution, isNull);
  });

  test('archivar oculta la cuenta sin borrar sus movimientos', () async {
    final id = await repo.create(
      name: 'Vieja',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    await repo.archive(id);
    final active = await repo.activeAccounts();
    expect(active.where((a) => a.id == id), isEmpty);
    expect(await repo.byId(id), isNotNull);
  });

  test('permite cambiar la divisa solo si la cuenta está vacía', () async {
    final id = await repo.create(
      name: 'Recién creada',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    await repo.changeCurrency(id, Currency.usd); // no lanza

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          type: TxType.expense,
          accountId: id,
          amountMinor: 500,
          currency: 'USD',
          fxRateToEurScaled: 100000000,
          amountEurMinor: 500,
          date: '2026-09-12',
        ));

    expect(
      () => repo.changeCurrency(id, Currency.gbp),
      throwsA(isA<StateError>()),
    );
  });
}
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/data/account_repository_test.dart`
Expected: FAIL — `account_repository.dart not found`.

- [ ] **Step 3: Implementar lo mínimo**

```dart
// lib/data/repositories/account_repository.dart
import 'package:drift/drift.dart';
import '../../core/currency.dart';
import '../db/database.dart';
import '../db/tables.dart';

/// Una institución con sus cuentas. `institution` es nulo para las cuentas
/// sueltas, como el efectivo.
class AccountGroup {
  final Institution? institution;
  final List<Account> accounts;
  const AccountGroup(this.institution, this.accounts);
}

class AccountRepository {
  final AppDatabase db;
  AccountRepository(this.db);

  Future<int> createInstitution({required String name, String icon = '🏦'}) =>
      db.into(db.institutions).insert(
            InstitutionsCompanion.insert(name: name, icon: Value(icon)),
          );

  Future<int> create({
    required String name,
    required Currency currency,
    required AccountType type,
    int? institutionId,
    int initialBalanceMinor = 0,
    int? creditLimitMinor,
  }) =>
      db.into(db.accounts).insert(AccountsCompanion.insert(
            name: name,
            currency: currency.code,
            type: type,
            institutionId: Value(institutionId),
            initialBalanceMinor: Value(initialBalanceMinor),
            creditLimitMinor: Value(creditLimitMinor),
          ));

  Future<Account> byId(int id) =>
      (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingle();

  Future<List<Account>> activeAccounts() => (db.select(db.accounts)
        ..where((a) => a.isArchived.equals(false))
        ..orderBy([(a) => OrderingTerm(expression: a.sortOrder)]))
      .get();

  Stream<List<Account>> watchActiveAccounts() => (db.select(db.accounts)
        ..where((a) => a.isArchived.equals(false))
        ..orderBy([(a) => OrderingTerm(expression: a.sortOrder)]))
      .watch();

  Future<void> archive(int id) => (db.update(db.accounts)
        ..where((a) => a.id.equals(id)))
      .write(const AccountsCompanion(isArchived: Value(true)));

  Future<void> rename(int id, String name) => (db.update(db.accounts)
        ..where((a) => a.id.equals(id)))
      .write(AccountsCompanion(name: Value(name)));

  /// La divisa es inmutable en cuanto la cuenta tiene movimientos: cambiarla
  /// reescribiría el histórico.
  Future<void> changeCurrency(int id, Currency currency) async {
    final count = await (db.selectOnly(db.transactions)
          ..addColumns([db.transactions.id.count()])
          ..where(db.transactions.accountId.equals(id) |
              db.transactions.counterAccountId.equals(id)))
        .getSingle();
    final used = count.read(db.transactions.id.count()) ?? 0;
    if (used > 0) {
      throw StateError(
        'La cuenta ya tiene movimientos: archívala y crea otra con la divisa correcta',
      );
    }
    await (db.update(db.accounts)..where((a) => a.id.equals(id)))
        .write(AccountsCompanion(currency: Value(currency.code)));
  }

  Future<List<AccountGroup>> groupedByInstitution() async {
    final institutions = await (db.select(db.institutions)
          ..orderBy([(i) => OrderingTerm(expression: i.sortOrder)]))
        .get();
    final accounts = await activeAccounts();

    final groups = <AccountGroup>[];
    for (final inst in institutions) {
      final mine = accounts.where((a) => a.institutionId == inst.id).toList();
      if (mine.isNotEmpty) groups.add(AccountGroup(inst, mine));
    }
    final loose = accounts.where((a) => a.institutionId == null).toList();
    if (loose.isNotEmpty) groups.add(AccountGroup(null, loose));
    return groups;
  }
}
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/data/account_repository_test.dart`
Expected: PASS, 4 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/account_repository.dart test/data/account_repository_test.dart
git commit -m "feat: add account repository with institution grouping"
```

---

## Task 11: Saldos calculados

**Files:**
- Modify: `lib/data/repositories/account_repository.dart`
- Test: `test/data/balance_test.dart`

El saldo no se almacena. Se calcula sobre el saldo inicial, y por eso no puede desincronizarse al editar el pasado.

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/data/balance_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/money.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/db/tables.dart';
import 'package:finanzas/data/repositories/account_repository.dart';

void main() {
  late AppDatabase db;
  late AccountRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AccountRepository(db);
  });
  tearDown(() => db.close());

  Future<void> insertTx({
    required TxType type,
    required int accountId,
    required int amountMinor,
    required String currency,
    int? counterAccountId,
    int? counterAmountMinor,
  }) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            type: type,
            accountId: accountId,
            amountMinor: amountMinor,
            currency: currency,
            fxRateToEurScaled: 100000000,
            amountEurMinor: amountMinor,
            date: '2026-09-12',
            counterAccountId: Value(counterAccountId),
            counterAmountMinor: Value(counterAmountMinor),
          ));

  test('el saldo parte del saldo inicial', () async {
    final id = await repo.create(
      name: 'BBVA',
      currency: Currency.eur,
      type: AccountType.checking,
      initialBalanceMinor: 100000,
    );
    expect(await repo.balanceOf(id), const Money(100000, Currency.eur));
  });

  test('los gastos restan y los ingresos suman', () async {
    final id = await repo.create(
      name: 'BBVA',
      currency: Currency.eur,
      type: AccountType.checking,
      initialBalanceMinor: 100000,
    );
    await insertTx(type: TxType.expense, accountId: id, amountMinor: 5230, currency: 'EUR');
    await insertTx(type: TxType.income, accountId: id, amountMinor: 240000, currency: 'EUR');
    expect(await repo.balanceOf(id), const Money(334770, Currency.eur));
  });

  test('una transferencia resta en origen y suma en destino', () async {
    final from = await repo.create(
      name: 'Barclays',
      currency: Currency.gbp,
      type: AccountType.checking,
      initialBalanceMinor: 120500,
    );
    final to = await repo.create(
      name: 'BBVA',
      currency: Currency.eur,
      type: AccountType.checking,
      initialBalanceMinor: 0,
    );
    // Salen 850,00 £ y entran 995,00 €
    await insertTx(
      type: TxType.transfer,
      accountId: from,
      amountMinor: 85000,
      currency: 'GBP',
      counterAccountId: to,
      counterAmountMinor: 99500,
    );
    expect(await repo.balanceOf(from), const Money(35500, Currency.gbp));
    expect(await repo.balanceOf(to), const Money(99500, Currency.eur));
  });

  test('una tarjeta de crédito puede quedar en negativo', () async {
    final card = await repo.create(
      name: 'Visa',
      currency: Currency.eur,
      type: AccountType.creditCard,
    );
    await insertTx(type: TxType.expense, accountId: card, amountMinor: 31240, currency: 'EUR');
    expect(await repo.balanceOf(card), const Money(-31240, Currency.eur));
  });
}
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/data/balance_test.dart`
Expected: FAIL — `The method 'balanceOf' isn't defined`.

- [ ] **Step 3: Añadir el cálculo al repositorio**

Añade estos imports al principio de `lib/data/repositories/account_repository.dart`:

```dart
import '../../core/money.dart';
```

Y estos métodos dentro de `class AccountRepository`:

```dart
  /// Saldo inicial, menos gastos y transferencias salientes, más ingresos y
  /// transferencias entrantes. Todo en la divisa nativa de la cuenta.
  static const String _balanceSql = '''
    SELECT a.id AS account_id,
           a.currency AS currency,
           a.initial_balance_minor
           + COALESCE((
               SELECT SUM(CASE t.type
                            WHEN 'income'   THEN  t.amount_minor
                            WHEN 'expense'  THEN -t.amount_minor
                            WHEN 'transfer' THEN -t.amount_minor
                          END)
               FROM transactions t WHERE t.account_id = a.id), 0)
           + COALESCE((
               SELECT SUM(t.counter_amount_minor)
               FROM transactions t
               WHERE t.counter_account_id = a.id AND t.type = 'transfer'), 0)
           AS balance_minor
    FROM accounts a
  ''';

  Future<Money> balanceOf(int accountId) async {
    final rows = await db
        .customSelect(
          '$_balanceSql WHERE a.id = ?1',
          variables: [Variable<int>(accountId)],
          readsFrom: {db.accounts, db.transactions},
        )
        .get();
    final row = rows.single;
    return Money(
      row.read<int>('balance_minor'),
      Currency.byCode(row.read<String>('currency')),
    );
  }

  /// Saldo de todas las cuentas activas, por id. Se recalcula solo cuando
  /// cambian las cuentas o los movimientos.
  Stream<Map<int, Money>> watchBalances() => db
      .customSelect(
        '$_balanceSql WHERE a.is_archived = 0',
        readsFrom: {db.accounts, db.transactions},
      )
      .watch()
      .map((rows) => {
            for (final row in rows)
              row.read<int>('account_id'): Money(
                row.read<int>('balance_minor'),
                Currency.byCode(row.read<String>('currency')),
              )
          });
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/data/balance_test.dart`
Expected: PASS, 4 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/account_repository.dart test/data/balance_test.dart
git commit -m "feat: compute account balances from transactions"
```

---

## Task 12: Repositorio de tipos de cambio

**Files:**
- Create: `lib/data/repositories/fx_repository.dart`
- Test: `test/data/fx_repository_test.dart`

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/data/fx_repository_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/fx.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/repositories/fx_repository.dart';

void main() {
  late AppDatabase db;
  late FxRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FxRepository(db);
  });
  tearDown(() => db.close());

  test('el euro siempre vale uno, sin consultar nada', () async {
    final resolved = await repo.rateFor(Currency.eur, '2026-09-12');
    expect(resolved.rate.scaled, FxRate.scale);
    expect(resolved.isEstimated, isFalse);
  });

  test('devuelve el tipo del día si existe', () async {
    await repo.save('2026-09-12', const FxRate(Currency.gbp, 117234500), source: 'ecb');
    final resolved = await repo.rateFor(Currency.gbp, '2026-09-12');
    expect(resolved.rate.scaled, 117234500);
    expect(resolved.isEstimated, isFalse);
  });

  test('usa el último tipo anterior y lo marca estimado', () async {
    // Viernes
    await repo.save('2026-09-11', const FxRate(Currency.gbp, 117234500), source: 'ecb');
    // Sábado: el BCE no publica
    final resolved = await repo.rateFor(Currency.gbp, '2026-09-12');
    expect(resolved.rate.scaled, 117234500);
    expect(resolved.isEstimated, isTrue);
  });

  test('sin ningún tipo conocido, avisa en vez de inventarse uno', () async {
    expect(
      () => repo.rateFor(Currency.usd, '2026-09-12'),
      throwsA(isA<NoFxRateAvailable>()),
    );
  });

  test('guardar dos veces el mismo día actualiza en vez de duplicar', () async {
    await repo.save('2026-09-12', const FxRate(Currency.gbp, 100000000), source: 'ecb');
    await repo.save('2026-09-12', const FxRate(Currency.gbp, 117234500), source: 'manual');
    final resolved = await repo.rateFor(Currency.gbp, '2026-09-12');
    expect(resolved.rate.scaled, 117234500);
  });
}
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/data/fx_repository_test.dart`
Expected: FAIL — `fx_repository.dart not found`.

- [ ] **Step 3: Implementar lo mínimo**

```dart
// lib/data/repositories/fx_repository.dart
import 'package:drift/drift.dart';
import '../../core/currency.dart';
import '../../core/fx.dart';
import '../db/database.dart';

/// No hay ningún tipo de cambio conocido para esta divisa.
class NoFxRateAvailable implements Exception {
  final Currency currency;
  NoFxRateAvailable(this.currency);

  @override
  String toString() =>
      'Sin tipo de cambio para ${currency.code}. Conéctate a internet una vez '
      'o introdúcelo a mano.';
}

/// Un tipo resuelto para una fecha concreta. [isEstimated] indica que se ha
/// usado el tipo de un día anterior.
class ResolvedRate {
  final FxRate rate;
  final bool isEstimated;
  const ResolvedRate(this.rate, this.isEstimated);
}

class FxRepository {
  final AppDatabase db;
  FxRepository(this.db);

  Future<void> save(String date, FxRate rate, {required String source}) =>
      db.into(db.fxRates).insertOnConflictUpdate(FxRatesCompanion.insert(
            date: date,
            currency: rate.currency.code,
            rateToEurScaled: rate.scaled,
            source: source,
          ));

  Future<void> saveAll(String date, List<FxRate> rates,
          {required String source}) =>
      db.batch((b) {
        for (final rate in rates) {
          b.insert(
            db.fxRates,
            FxRatesCompanion.insert(
              date: date,
              currency: rate.currency.code,
              rateToEurScaled: rate.scaled,
              source: source,
            ),
            onConflict: DoUpdate((_) => FxRatesCompanion(
                  rateToEurScaled: Value(rate.scaled),
                  source: Value(source),
                )),
          );
        }
      });

  /// El tipo del día, o el último anterior marcado como estimado.
  Future<ResolvedRate> rateFor(Currency currency, String date) async {
    if (currency == Currency.eur) {
      return ResolvedRate(FxRate.identity(Currency.eur), false);
    }

    final exact = await (db.select(db.fxRates)
          ..where((r) => r.currency.equals(currency.code) & r.date.equals(date)))
        .getSingleOrNull();
    if (exact != null) {
      return ResolvedRate(FxRate(currency, exact.rateToEurScaled), false);
    }

    final previous = await (db.select(db.fxRates)
          ..where((r) =>
              r.currency.equals(currency.code) & r.date.isSmallerThanValue(date))
          ..orderBy([(r) => OrderingTerm(expression: r.date, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    if (previous != null) {
      return ResolvedRate(FxRate(currency, previous.rateToEurScaled), true);
    }

    throw NoFxRateAvailable(currency);
  }

  Future<String?> latestStoredDate() async {
    final row = await (db.select(db.fxRates)
          ..orderBy([(r) => OrderingTerm(expression: r.date, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row?.date;
  }
}
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/data/fx_repository_test.dart`
Expected: PASS, 5 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/fx_repository.dart test/data/fx_repository_test.dart
git commit -m "feat: add FX rate repository with stale-rate fallback"
```

---

## Task 13: Descarga de tipos del BCE

**Files:**
- Create: `lib/data/services/ecb_fx_service.dart`
- Test: `test/data/ecb_fx_service_test.dart`

El BCE publica en `https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml`, sin registro ni clave. Da «unidades de divisa por euro»; nosotros guardamos lo contrario.

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/data/ecb_fx_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/data/services/ecb_fx_service.dart';

const _xml = '''<?xml version="1.0" encoding="UTF-8"?>
<gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01"
                 xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
  <Cube>
    <Cube time="2026-09-11">
      <Cube currency="USD" rate="1.0842"/>
      <Cube currency="GBP" rate="0.85300"/>
      <Cube currency="JPY" rate="161.23"/>
    </Cube>
  </Cube>
</gesmes:Envelope>''';

void main() {
  test('extrae la fecha de publicación', () {
    expect(parseEcbDaily(_xml).date, '2026-09-11');
  });

  test('invierte las cotizaciones a euros por unidad', () {
    final rates = parseEcbDaily(_xml).rates;
    final gbp = rates.firstWhere((r) => r.currency == Currency.gbp);
    // 1 / 0,853 = 1,17233...
    expect(gbp.scaled, closeTo(117233294, 2));
  });

  test('ignora las divisas que la app no soporta', () {
    final rates = parseEcbDaily(_xml).rates;
    expect(rates.map((r) => r.currency.code), containsAll(['USD', 'GBP']));
    expect(rates.length, 2); // el yen se descarta
  });

  test('un XML sin cotizaciones es un error de formato', () {
    expect(() => parseEcbDaily('<vacio/>'), throwsFormatException);
  });
}
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/data/ecb_fx_service_test.dart`
Expected: FAIL — `ecb_fx_service.dart not found`.

- [ ] **Step 3: Implementar lo mínimo**

El parseo se hace con expresiones regulares sobre un XML plano y estable de tres niveles, para no añadir una dependencia más.

```dart
// lib/data/services/ecb_fx_service.dart
import 'package:http/http.dart' as http;
import '../../core/currency.dart';
import '../../core/fx.dart';
import '../repositories/fx_repository.dart';

class EcbDaily {
  final String date;
  final List<FxRate> rates;
  const EcbDaily(this.date, this.rates);
}

final _dateRe = RegExp(r'time="(\d{4}-\d{2}-\d{2})"');
final _rateRe = RegExp(r'currency="([A-Z]{3})"\s+rate="([\d.]+)"');

/// Convierte el XML diario del BCE en tipos «euros por unidad».
EcbDaily parseEcbDaily(String xml) {
  final dateMatch = _dateRe.firstMatch(xml);
  final matches = _rateRe.allMatches(xml).toList();
  if (dateMatch == null || matches.isEmpty) {
    throw const FormatException('El XML del BCE no tiene el formato esperado');
  }

  final supported = Currency.all.map((c) => c.code).toSet();
  final rates = <FxRate>[];
  for (final m in matches) {
    final code = m.group(1)!;
    if (!supported.contains(code)) continue;
    rates.add(FxRate.fromEcbQuote(Currency.byCode(code), double.parse(m.group(2)!)));
  }
  return EcbDaily(dateMatch.group(1)!, rates);
}

class EcbFxService {
  static final Uri _endpoint =
      Uri.parse('https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml');

  final FxRepository repo;
  final http.Client client;

  EcbFxService(this.repo, {http.Client? client})
      : client = client ?? http.Client();

  /// Descarga los tipos del día y los guarda. Devuelve `false` si no se pudo
  /// (sin conexión, servicio caído): la app sigue funcionando con lo que tenga.
  Future<bool> refresh() async {
    try {
      final response = await client.get(_endpoint).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      final daily = parseEcbDaily(response.body);
      await repo.saveAll(daily.date, daily.rates, source: 'ecb');
      return true;
    } catch (_) {
      return false;
    }
  }
}
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/data/ecb_fx_service_test.dart`
Expected: PASS, 4 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/data/services/ecb_fx_service.dart test/data/ecb_fx_service_test.dart
git commit -m "feat: fetch daily FX rates from the ECB"
```

---

## Task 14: Alta de gastos e ingresos

**Files:**
- Create: `lib/data/repositories/transaction_repository.dart`
- Test: `test/data/transaction_repository_test.dart`

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/data/transaction_repository_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/fx.dart';
import 'package:finanzas/core/money.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/db/tables.dart';
import 'package:finanzas/data/repositories/account_repository.dart';
import 'package:finanzas/data/repositories/fx_repository.dart';
import 'package:finanzas/data/repositories/transaction_repository.dart';

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late FxRepository fx;
  late TransactionRepository repo;
  late int revolutGbp;
  late int comida;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    accounts = AccountRepository(db);
    fx = FxRepository(db);
    repo = TransactionRepository(db, accounts, fx);

    revolutGbp = await accounts.create(
      name: 'Libras',
      currency: Currency.gbp,
      type: AccountType.checking,
    );
    comida = (await db.select(db.categories).get())
        .firstWhere((c) => c.name == 'Restaurantes')
        .id;
    await fx.save('2026-09-12', const FxRate(Currency.gbp, 117234500), source: 'ecb');
  });
  tearDown(() => db.close());

  test('un gasto hereda la divisa de su cuenta', () async {
    final id = await repo.addExpense(
      accountId: revolutGbp,
      amountMinor: 2450,
      categoryId: comida,
      date: '2026-09-12',
    );
    final tx = await repo.byId(id);
    expect(tx.currency, 'GBP');
    expect(tx.type, TxType.expense);
    expect(tx.amountMinor, 2450); // siempre positivo
  });

  test('congela el tipo de cambio y el importe en euros', () async {
    final id = await repo.addExpense(
      accountId: revolutGbp,
      amountMinor: 2450,
      categoryId: comida,
      date: '2026-09-12',
    );
    final tx = await repo.byId(id);
    expect(tx.fxRateToEurScaled, 117234500);
    expect(tx.amountEurMinor, 2872);
    expect(tx.fxIsEstimated, isFalse);
  });

  test('marca el movimiento cuando el tipo es de otro día', () async {
    final id = await repo.addExpense(
      accountId: revolutGbp,
      amountMinor: 1000,
      categoryId: comida,
      date: '2026-09-13', // no hay tipo de ese día
    );
    expect((await repo.byId(id)).fxIsEstimated, isTrue);
  });

  test('un importe de cero o negativo se rechaza', () async {
    expect(
      () => repo.addExpense(
          accountId: revolutGbp, amountMinor: 0, categoryId: comida, date: '2026-09-12'),
      throwsArgumentError,
    );
    expect(
      () => repo.addExpense(
          accountId: revolutGbp, amountMinor: -5, categoryId: comida, date: '2026-09-12'),
      throwsArgumentError,
    );
  });

  test('un ingreso suma al saldo', () async {
    await repo.addIncome(
      accountId: revolutGbp,
      amountMinor: 50000,
      categoryId: null,
      date: '2026-09-12',
    );
    expect(await accounts.balanceOf(revolutGbp), const Money(50000, Currency.gbp));
  });

  test('borrar un movimiento devuelve el saldo a su sitio', () async {
    final id = await repo.addExpense(
      accountId: revolutGbp,
      amountMinor: 2450,
      categoryId: comida,
      date: '2026-09-12',
    );
    await repo.delete(id);
    expect(await accounts.balanceOf(revolutGbp), const Money(0, Currency.gbp));
  });
}
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/data/transaction_repository_test.dart`
Expected: FAIL — `transaction_repository.dart not found`.

- [ ] **Step 3: Implementar lo mínimo**

```dart
// lib/data/repositories/transaction_repository.dart
import 'package:drift/drift.dart';
import '../../core/currency.dart';
import '../../core/money.dart';
import '../db/database.dart';
import '../db/tables.dart';
import 'account_repository.dart';
import 'fx_repository.dart';

class TransactionRepository {
  final AppDatabase db;
  final AccountRepository accounts;
  final FxRepository fx;

  TransactionRepository(this.db, this.accounts, this.fx);

  Future<Txn> byId(int id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();

  Future<int> addExpense({
    required int accountId,
    required int amountMinor,
    required int? categoryId,
    required String date,
    String? merchant,
    String? note,
  }) =>
      _addSimple(
        type: TxType.expense,
        accountId: accountId,
        amountMinor: amountMinor,
        categoryId: categoryId,
        date: date,
        merchant: merchant,
        note: note,
      );

  Future<int> addIncome({
    required int accountId,
    required int amountMinor,
    required int? categoryId,
    required String date,
    String? merchant,
    String? note,
  }) =>
      _addSimple(
        type: TxType.income,
        accountId: accountId,
        amountMinor: amountMinor,
        categoryId: categoryId,
        date: date,
        merchant: merchant,
        note: note,
      );

  Future<int> _addSimple({
    required TxType type,
    required int accountId,
    required int amountMinor,
    required int? categoryId,
    required String date,
    String? merchant,
    String? note,
  }) async {
    _requirePositive(amountMinor);
    final account = await accounts.byId(accountId);
    final currency = Currency.byCode(account.currency);
    final resolved = await fx.rateFor(currency, date);
    final eur = resolved.rate.toEur(Money(amountMinor, currency));

    return db.into(db.transactions).insert(TransactionsCompanion.insert(
          type: type,
          accountId: accountId,
          amountMinor: amountMinor,
          currency: currency.code,
          fxRateToEurScaled: resolved.rate.scaled,
          amountEurMinor: eur.minorUnits,
          fxIsEstimated: Value(resolved.isEstimated),
          date: date,
          categoryId: Value(categoryId),
          merchant: Value(merchant),
          note: Value(note),
        ));
  }

  Future<void> delete(int id) =>
      (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();

  static void _requirePositive(int amountMinor) {
    if (amountMinor <= 0) {
      throw ArgumentError('El importe debe ser mayor que cero: $amountMinor');
    }
  }
}
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/data/transaction_repository_test.dart`
Expected: PASS, 6 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/transaction_repository.dart test/data/transaction_repository_test.dart
git commit -m "feat: add expenses and income with frozen FX rates"
```

---

## Task 15: Transferencias, incluidas las que cambian de divisa

**Files:**
- Modify: `lib/data/repositories/transaction_repository.dart`
- Test: `test/data/transfer_test.dart`

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/data/transfer_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/fx.dart';
import 'package:finanzas/core/money.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/db/tables.dart';
import 'package:finanzas/data/repositories/account_repository.dart';
import 'package:finanzas/data/repositories/fx_repository.dart';
import 'package:finanzas/data/repositories/transaction_repository.dart';

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late TransactionRepository repo;
  late int barclays;
  late int bbva;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    accounts = AccountRepository(db);
    final fx = FxRepository(db);
    repo = TransactionRepository(db, accounts, fx);

    barclays = await accounts.create(
      name: 'Barclays',
      currency: Currency.gbp,
      type: AccountType.checking,
      initialBalanceMinor: 120500,
    );
    bbva = await accounts.create(
      name: 'BBVA',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    await fx.save('2026-09-12', const FxRate(Currency.gbp, 117234500), source: 'ecb');
  });
  tearDown(() => db.close());

  test('mueve el dinero de una cuenta a otra', () async {
    await repo.addTransfer(
      fromAccountId: barclays,
      toAccountId: bbva,
      amountMinor: 85000,
      counterAmountMinor: 99500,
      date: '2026-09-12',
    );
    expect(await accounts.balanceOf(barclays), const Money(35500, Currency.gbp));
    expect(await accounts.balanceOf(bbva), const Money(99500, Currency.eur));
  });

  test('es una sola fila, no dos', () async {
    await repo.addTransfer(
      fromAccountId: barclays,
      toAccountId: bbva,
      amountMinor: 85000,
      counterAmountMinor: 99500,
      date: '2026-09-12',
    );
    expect((await db.select(db.transactions).get()).length, 1);
  });

  test('deduce el tipo real aplicado por el banco', () async {
    final id = await repo.addTransfer(
      fromAccountId: barclays,
      toAccountId: bbva,
      amountMinor: 85000,
      counterAmountMinor: 99500,
      date: '2026-09-12',
    );
    // 995,00 / 850,00 = 1,17058823...
    expect(repo.effectiveRateOf(await repo.byId(id)), closeTo(1.170588, 0.000001));
  });

  test('si ambas cuentas comparten divisa, los importes deben coincidir', () async {
    final otraEur = await accounts.create(
      name: 'Ahorro',
      currency: Currency.eur,
      type: AccountType.savings,
    );
    expect(
      () => repo.addTransfer(
        fromAccountId: bbva,
        toAccountId: otraEur,
        amountMinor: 10000,
        counterAmountMinor: 9000,
        date: '2026-09-12',
      ),
      throwsArgumentError,
    );
  });

  test('no se puede transferir una cuenta a sí misma', () async {
    expect(
      () => repo.addTransfer(
        fromAccountId: bbva,
        toAccountId: bbva,
        amountMinor: 10000,
        counterAmountMinor: 10000,
        date: '2026-09-12',
      ),
      throwsArgumentError,
    );
  });

  test('las transferencias no cuentan como gasto ni como ingreso', () async {
    await repo.addTransfer(
      fromAccountId: barclays,
      toAccountId: bbva,
      amountMinor: 85000,
      counterAmountMinor: 99500,
      date: '2026-09-12',
    );
    final gasto = await repo.totalEurBetween(
      from: '2026-09-01',
      to: '2026-09-30',
      type: TxType.expense,
    );
    expect(gasto, Money.zero(Currency.eur));
  });
}
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/data/transfer_test.dart`
Expected: FAIL — `The method 'addTransfer' isn't defined`.

- [ ] **Step 3: Añadir las transferencias al repositorio**

Añade estos métodos dentro de `class TransactionRepository`:

```dart
  /// Una transferencia es una sola fila con las dos cuentas y los dos
  /// importes. Así no puede existir media transferencia.
  Future<int> addTransfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountMinor,
    required int counterAmountMinor,
    required String date,
    String? note,
  }) async {
    _requirePositive(amountMinor);
    _requirePositive(counterAmountMinor);
    if (fromAccountId == toAccountId) {
      throw ArgumentError('El origen y el destino no pueden ser la misma cuenta');
    }

    final from = await accounts.byId(fromAccountId);
    final to = await accounts.byId(toAccountId);
    if (from.currency == to.currency && amountMinor != counterAmountMinor) {
      throw ArgumentError(
        'Entre cuentas de la misma divisa los importes deben coincidir',
      );
    }

    final currency = Currency.byCode(from.currency);
    final resolved = await fx.rateFor(currency, date);
    final eur = resolved.rate.toEur(Money(amountMinor, currency));

    return db.into(db.transactions).insert(TransactionsCompanion.insert(
          type: TxType.transfer,
          accountId: fromAccountId,
          amountMinor: amountMinor,
          currency: currency.code,
          fxRateToEurScaled: resolved.rate.scaled,
          amountEurMinor: eur.minorUnits,
          fxIsEstimated: Value(resolved.isEstimated),
          date: date,
          counterAccountId: Value(toAccountId),
          counterAmountMinor: Value(counterAmountMinor),
          note: Value(note),
        ));
  }

  /// El tipo que realmente aplicó el banco, comisión incluida.
  double effectiveRateOf(Txn tx) {
    final counter = tx.counterAmountMinor;
    if (tx.type != TxType.transfer || counter == null || tx.amountMinor == 0) {
      return 1;
    }
    return counter / tx.amountMinor;
  }

  /// Total en euros de un tipo de movimiento en un rango de fechas.
  ///
  /// Las transferencias quedan fuera de gastos e ingresos por construcción:
  /// mover dinero entre cuentas propias no es ni gastar ni ingresar.
  Future<Money> totalEurBetween({
    required String from,
    required String to,
    required TxType type,
  }) async {
    final sum = db.transactions.amountEurMinor.sum();
    final row = await (db.selectOnly(db.transactions)
          ..addColumns([sum])
          ..where(db.transactions.type.equalsValue(type) &
              db.transactions.date.isBiggerOrEqualValue(from) &
              db.transactions.date.isSmallerOrEqualValue(to)))
        .getSingle();
    return Money(row.read(sum) ?? 0, Currency.eur);
  }
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/data/transfer_test.dart`
Expected: PASS, 6 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/transaction_repository.dart test/data/transfer_test.dart
git commit -m "feat: add cross-currency transfers as single rows"
```

---

## Task 16: Patrimonio total en euros

**Files:**
- Modify: `lib/data/repositories/account_repository.dart`
- Test: `test/data/net_worth_test.dart`

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/data/net_worth_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/fx.dart';
import 'package:finanzas/core/money.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/db/tables.dart';
import 'package:finanzas/data/repositories/account_repository.dart';
import 'package:finanzas/data/repositories/fx_repository.dart';

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late FxRepository fx;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    accounts = AccountRepository(db);
    fx = FxRepository(db);
    await fx.save('2026-09-12', const FxRate(Currency.gbp, 117234500), source: 'ecb');
    await fx.save('2026-09-12', const FxRate(Currency.usd, 92234000), source: 'ecb');
  });
  tearDown(() => db.close());

  test('suma cuentas de tres divisas convertidas a euros', () async {
    await accounts.create(
      name: 'BBVA',
      currency: Currency.eur,
      type: AccountType.checking,
      initialBalanceMinor: 320455,
    );
    await accounts.create(
      name: 'Barclays',
      currency: Currency.gbp,
      type: AccountType.checking,
      initialBalanceMinor: 120500,
    );
    await accounts.create(
      name: 'Chase',
      currency: Currency.usd,
      type: AccountType.checking,
      initialBalanceMinor: 190000,
    );

    // 3204,55 € + (1205,00 £ × 1,172345) + (1900,00 $ × 0,92234)
    // = 320455 + 141267 + 175245 céntimos
    final total = await accounts.netWorthEur(fx, '2026-09-12');
    expect(total, const Money(636967, Currency.eur));
  });

  test('las tarjetas en negativo restan del patrimonio', () async {
    await accounts.create(
      name: 'BBVA',
      currency: Currency.eur,
      type: AccountType.checking,
      initialBalanceMinor: 100000,
    );
    final card = await accounts.create(
      name: 'Visa',
      currency: Currency.eur,
      type: AccountType.creditCard,
      initialBalanceMinor: -31240,
    );
    expect(await accounts.balanceOf(card), const Money(-31240, Currency.eur));
    expect(await accounts.netWorthEur(fx, '2026-09-12'),
        const Money(68760, Currency.eur));
  });

  test('sin cuentas, el patrimonio es cero euros', () async {
    expect(await accounts.netWorthEur(fx, '2026-09-12'), Money.zero(Currency.eur));
  });

  test('las cuentas archivadas no cuentan', () async {
    final id = await accounts.create(
      name: 'Vieja',
      currency: Currency.eur,
      type: AccountType.checking,
      initialBalanceMinor: 500000,
    );
    await accounts.archive(id);
    expect(await accounts.netWorthEur(fx, '2026-09-12'), Money.zero(Currency.eur));
  });
}
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/data/net_worth_test.dart`
Expected: FAIL — `The method 'netWorthEur' isn't defined`.

- [ ] **Step 3: Añadir el cálculo**

Añade el import de `FxRepository` al principio de `lib/data/repositories/account_repository.dart`:

```dart
import 'fx_repository.dart';
```

Y este método dentro de `class AccountRepository`:

```dart
  /// Suma de todas las cuentas activas, convertidas a euros con los tipos de
  /// [date]. Las tarjetas en negativo restan.
  Future<Money> netWorthEur(FxRepository fx, String date) async {
    final rows = await db
        .customSelect(
          '$_balanceSql WHERE a.is_archived = 0',
          readsFrom: {db.accounts, db.transactions},
        )
        .get();

    var totalMinor = 0;
    for (final row in rows) {
      final currency = Currency.byCode(row.read<String>('currency'));
      final balance = Money(row.read<int>('balance_minor'), currency);
      final resolved = await fx.rateFor(currency, date);
      totalMinor += resolved.rate.toEur(balance).minorUnits;
    }
    return Money(totalMinor, Currency.eur);
  }
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/data/net_worth_test.dart`
Expected: PASS, 4 pruebas.

Si el primer caso falla por uno o dos céntimos, imprime el valor real y ajusta la **prueba**: el redondeo por cuenta es el comportamiento correcto y deliberado.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/account_repository.dart test/data/net_worth_test.dart
git commit -m "feat: compute total net worth in EUR across currencies"
```

---

## Task 17: Cableado de la app

**Files:**
- Create: `lib/app/providers.dart`, `lib/app/app.dart`
- Modify: `lib/main.dart`
- Delete: `test/widget_test.dart`

- [ ] **Step 1: Escribir los providers**

```dart
// lib/app/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/civil_date.dart';
import '../core/money.dart';
import '../data/db/database.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/fx_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/services/ecb_fx_service.dart';

final dbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final accountRepoProvider =
    Provider((ref) => AccountRepository(ref.watch(dbProvider)));

final fxRepoProvider = Provider((ref) => FxRepository(ref.watch(dbProvider)));

final transactionRepoProvider = Provider((ref) => TransactionRepository(
      ref.watch(dbProvider),
      ref.watch(accountRepoProvider),
      ref.watch(fxRepoProvider),
    ));

final ecbServiceProvider =
    Provider((ref) => EcbFxService(ref.watch(fxRepoProvider)));

/// Se lanza una vez al arrancar. Si falla, la app sigue con lo que tenga.
final fxRefreshProvider = FutureProvider<bool>(
    (ref) => ref.watch(ecbServiceProvider).refresh());

final accountsProvider = StreamProvider(
    (ref) => ref.watch(accountRepoProvider).watchActiveAccounts());

final balancesProvider = StreamProvider<Map<int, Money>>(
    (ref) => ref.watch(accountRepoProvider).watchBalances());

final netWorthProvider = FutureProvider<Money>((ref) async {
  // Depende de los saldos para recalcularse cuando cambie un movimiento.
  ref.watch(balancesProvider);
  await ref.watch(fxRefreshProvider.future);
  return ref
      .watch(accountRepoProvider)
      .netWorthEur(ref.watch(fxRepoProvider), todayCivil());
});
```

- [ ] **Step 2: Escribir la app y el punto de entrada**

```dart
// lib/app/app.dart
import 'package:flutter/material.dart';

class FinanzasApp extends StatelessWidget {
  const FinanzasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finanzas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF12A150)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF12A150),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _Placeholder(),
    );
  }
}

/// Marcador de posición hasta la tarea 23, que trae la pantalla real.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Finanzas')),
      );
}
```

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

void main() {
  runApp(const ProviderScope(child: FinanzasApp()));
}
```

- [ ] **Step 3: Borrar la prueba de ejemplo de Flutter**

Prueba el contador que ya no existe.

```bash
rm test/widget_test.dart
```

- [ ] **Step 4: Verificar que todo sigue pasando**

Run: `flutter test`
Expected: PASS, todas las pruebas de las tareas 3–16.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: wire up Riverpod providers and app shell"
```

---

## Task 18: Consultas del mes y repositorio de categorías

**Files:**
- Create: `lib/data/repositories/category_repository.dart`
- Modify: `lib/app/providers.dart`, `lib/data/repositories/transaction_repository.dart`

Las piezas de datos que necesitan la hoja de añadir y la pantalla de inicio. Se hacen antes que las pantallas para que cada commit siga compilando.

- [ ] **Step 1: Añadir el provider de movimientos del mes**

Añade al final de `lib/app/providers.dart`:

```dart
final monthTransactionsProvider = StreamProvider((ref) {
  final now = DateTime.now();
  return ref.watch(transactionRepoProvider).watchBetween(
        from: firstDayOfMonth(now),
        to: lastDayOfMonth(now),
      );
});
```

- [ ] **Step 2: Añadir la consulta al repositorio**

Añade dentro de `class TransactionRepository` en `lib/data/repositories/transaction_repository.dart`:

```dart
  Stream<List<Txn>> watchBetween({required String from, required String to}) =>
      (db.select(db.transactions)
            ..where((t) =>
                t.date.isBiggerOrEqualValue(from) &
                t.date.isSmallerOrEqualValue(to))
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
              (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
            ]))
          .watch();
```

- [ ] **Step 3: Añadir el provider de categorías**

Añade al final de `lib/app/providers.dart`:

```dart
final categoryRepoProvider =
    Provider((ref) => CategoryRepository(ref.watch(dbProvider)));

final categoriesProvider = StreamProvider(
    (ref) => ref.watch(categoryRepoProvider).watchActive());
```

Y el import correspondiente arriba del archivo:

```dart
import '../data/repositories/category_repository.dart';
```

- [ ] **Step 4: Crear el repositorio de categorías**

```dart
// lib/data/repositories/category_repository.dart
import 'package:drift/drift.dart';
import '../db/database.dart';
import '../db/tables.dart';

class CategoryRepository {
  final AppDatabase db;
  CategoryRepository(this.db);

  Stream<List<Category>> watchActive() => (db.select(db.categories)
        ..where((c) => c.isArchived.equals(false))
        ..orderBy([(c) => OrderingTerm(expression: c.sortOrder)]))
      .watch();

  Future<List<Category>> ofKind(CategoryKind kind) => (db.select(db.categories)
        ..where((c) => c.isArchived.equals(false) & c.kind.equalsValue(kind))
        ..orderBy([(c) => OrderingTerm(expression: c.sortOrder)]))
      .get();

  Future<int> create({
    required String name,
    required CategoryKind kind,
    String icon = '🏷️',
  }) =>
      db.into(db.categories).insert(
            CategoriesCompanion.insert(name: name, kind: kind, icon: Value(icon)),
          );

  /// Se archiva, no se borra: los movimientos conservan su categoría.
  Future<void> archive(int id) => (db.update(db.categories)
        ..where((c) => c.id.equals(id)))
      .write(const CategoriesCompanion(isArchived: Value(true)));
}
```

- [ ] **Step 5: Verificar y confirmar**

```bash
flutter analyze
flutter test
```

Expected: `No issues found!` y todas las pruebas en verde.

```bash
git add -A
git commit -m "feat: add category repository and month queries"
```

---

## Task 19: La hoja de añadir — importe y teclado

**Files:**
- Create: `lib/features/transactions/add_sheet.dart`
- Test: `test/features/amount_input_test.dart`

- [ ] **Step 1: Escribir la prueba que falla**

La lógica del teclado se prueba aparte del widget: es donde están los errores.

```dart
// test/features/amount_input_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/features/transactions/amount_input.dart';

void main() {
  test('empieza en cero', () {
    expect(AmountInput().minorUnits, 0);
  });

  test('cada dígito desplaza a la izquierda', () {
    final input = AmountInput();
    input.pressDigit(2);
    input.pressDigit(4);
    input.pressDigit(5);
    input.pressDigit(0);
    expect(input.minorUnits, 2450); // 24,50
  });

  test('borrar quita el último dígito', () {
    final input = AmountInput()
      ..pressDigit(2)
      ..pressDigit(4)
      ..backspace();
    expect(input.minorUnits, 2);
  });

  test('no crece más allá del límite razonable', () {
    final input = AmountInput();
    for (var i = 0; i < 15; i++) {
      input.pressDigit(9);
    }
    expect(input.minorUnits, 999999999999); // 12 dígitos como tope
  });

  test('se formatea con los decimales de la divisa', () {
    final input = AmountInput()..pressDigit(5);
    expect(input.display(2), '0,05');
    input.pressDigit(0);
    expect(input.display(2), '0,50');
  });
}
```

- [ ] **Step 2: Ejecutar la prueba para verla fallar**

Run: `flutter test test/features/amount_input_test.dart`
Expected: FAIL — `amount_input.dart not found`.

- [ ] **Step 3: Implementar lo mínimo**

```dart
// lib/features/transactions/amount_input.dart

/// El importe que se está tecleando, como en una calculadora: los dígitos
/// entran por la derecha y los decimales salen solos.
class AmountInput {
  static const int _maxDigits = 12;

  int _minorUnits = 0;

  int get minorUnits => _minorUnits;
  bool get isEmpty => _minorUnits == 0;

  void pressDigit(int digit) {
    assert(digit >= 0 && digit <= 9);
    final next = _minorUnits * 10 + digit;
    if (next.toString().length > _maxDigits) return;
    _minorUnits = next;
  }

  void backspace() => _minorUnits ~/= 10;

  void clear() => _minorUnits = 0;

  /// «24,50» — sin símbolo de divisa, que lo pone la pantalla.
  String display(int decimalDigits) {
    final text = _minorUnits.toString().padLeft(decimalDigits + 1, '0');
    final cut = text.length - decimalDigits;
    return '${text.substring(0, cut)},${text.substring(cut)}';
  }
}
```

- [ ] **Step 4: Ejecutar la prueba para verla pasar**

Run: `flutter test test/features/amount_input_test.dart`
Expected: PASS, 5 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/features/transactions/amount_input.dart test/features/amount_input_test.dart
git commit -m "feat: add calculator-style amount input"
```

---

## Task 20: La hoja de añadir — cuentas, categorías y guardado

**Files:**
- Create: `lib/features/transactions/add_sheet.dart`
- Modify: `lib/app/providers.dart`

- [ ] **Step 1: Escribir la hoja**

```dart
// lib/features/transactions/add_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/civil_date.dart';
import '../../core/currency.dart';
import '../../core/formatting.dart';
import '../../core/money.dart';
import '../../data/db/database.dart';
import '../../data/db/tables.dart';
import '../../data/repositories/fx_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import 'amount_input.dart';

Future<void> showAddSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddSheet(),
    );

class AddSheet extends ConsumerStatefulWidget {
  const AddSheet({super.key});

  @override
  ConsumerState<AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<AddSheet> {
  final _amount = AmountInput();
  TxType _type = TxType.expense;
  int? _accountId;
  int? _counterAccountId;
  int? _categoryId;
  String _date = todayCivil();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];

    if (accounts.isEmpty) {
      return const _NoAccountsYet();
    }

    _accountId ??= accounts.first.id;
    final account = accounts.firstWhere((a) => a.id == _accountId,
        orElse: () => accounts.first);
    final currency = Currency.byCode(account.currency);

    final kind = _type == TxType.income ? CategoryKind.income : CategoryKind.expense;
    final visibleCategories = categories.where((c) => c.kind == kind).toList();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _grabber(context),
            const SizedBox(height: 10),
            _typeSelector(),
            const SizedBox(height: 14),
            _amountDisplay(currency),
            const SizedBox(height: 14),
            _label(_type == TxType.transfer ? 'Desde' : 'Cuenta'),
            _accountChips(accounts, selected: _accountId!, onPick: (id) {
              setState(() => _accountId = id);
            }),
            if (_type == TxType.transfer) ...[
              const SizedBox(height: 12),
              _label('Hasta'),
              _accountChips(
                accounts.where((a) => a.id != _accountId).toList(),
                selected: _counterAccountId,
                onPick: (id) => setState(() => _counterAccountId = id),
              ),
            ] else ...[
              const SizedBox(height: 12),
              _label('Categoría'),
              _categoryChips(visibleCategories),
            ],
            const SizedBox(height: 14),
            _keypad(currency),
          ],
        ),
      ),
    );
  }

  Widget _grabber(BuildContext context) => Container(
        width: 34,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(3),
        ),
      );

  Widget _typeSelector() => SegmentedButton<TxType>(
        segments: const [
          ButtonSegment(value: TxType.expense, label: Text('Gasto')),
          ButtonSegment(value: TxType.income, label: Text('Ingreso')),
          ButtonSegment(value: TxType.transfer, label: Text('Transfer.')),
        ],
        selected: {_type},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() {
          _type = s.first;
          _categoryId = null;
          _counterAccountId = null;
        }),
      );

  Widget _amountDisplay(Currency currency) {
    final money = Money(_amount.minorUnits, currency);
    return Column(
      children: [
        Text(
          '${_amount.display(currency.decimalDigits)} ${currency.symbol}',
          style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        if (currency != Currency.eur)
          _EurEquivalent(money: money, date: _date)
        else
          Text(currency.code, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _label(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(text.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall),
        ),
      );

  Widget _accountChips(List<Account> accounts,
      {required int? selected, required ValueChanged<int> onPick}) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: accounts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final a = accounts[i];
          final symbol = Currency.byCode(a.currency).symbol;
          return ChoiceChip(
            label: Text('${a.name} $symbol'),
            selected: a.id == selected,
            onSelected: (_) => onPick(a.id),
          );
        },
      ),
    );
  }

  Widget _categoryChips(List<Category> categories) => SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final c = categories[i];
            return ChoiceChip(
              label: Text('${c.icon} ${c.name}'),
              selected: c.id == _categoryId,
              onSelected: (_) => setState(() => _categoryId = c.id),
            );
          },
        ),
      );

  Widget _keypad(Currency currency) {
    Widget key(String label, VoidCallback onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: FilledButton.tonal(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(label, style: const TextStyle(fontSize: 17)),
            ),
          ),
        );

    Widget digitRow(List<int> digits) => Row(
          children: [
            for (final d in digits)
              key('$d', () => setState(() => _amount.pressDigit(d))),
          ],
        );

    return Column(
      children: [
        digitRow([1, 2, 3]),
        digitRow([4, 5, 6]),
        digitRow([7, 8, 9]),
        Row(
          children: [
            key('⌫', () => setState(_amount.backspace)),
            key('0', () => setState(() => _amount.pressDigit(0))),
            key('📅', _pickDate),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _canSave ? _save : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Guardar'),
          ),
        ),
      ],
    );
  }

  bool get _canSave {
    if (_saving || _amount.isEmpty || _accountId == null) return false;
    if (_type == TxType.transfer) return _counterAccountId != null;
    return true;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseCivilDate(_date),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = civilDateOf(picked));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(transactionRepoProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      if (_type == TxType.expense) {
        await repo.addExpense(
          accountId: _accountId!,
          amountMinor: _amount.minorUnits,
          categoryId: _categoryId,
          date: _date,
        );
      } else if (_type == TxType.income) {
        await repo.addIncome(
          accountId: _accountId!,
          amountMinor: _amount.minorUnits,
          categoryId: _categoryId,
          date: _date,
        );
      } else {
        final done = await _saveTransfer(repo);
        if (!done) return; // el usuario canceló el segundo importe
      }
      navigator.pop();
    } on NoFxRateAvailable catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  /// Devuelve `false` si el usuario canceló el diálogo del segundo importe.
  Future<bool> _saveTransfer(TransactionRepository repo) async {
    final accounts = ref.read(accountsProvider).value!;
    final from = accounts.firstWhere((a) => a.id == _accountId);
    final to = accounts.firstWhere((a) => a.id == _counterAccountId);

    var counterAmount = _amount.minorUnits;
    if (from.currency != to.currency) {
      final entered = await _askCounterAmount(Currency.byCode(to.currency));
      if (entered == null) {
        setState(() => _saving = false);
        return false;
      }
      counterAmount = entered;
    }

    await repo.addTransfer(
      fromAccountId: _accountId!,
      toAccountId: _counterAccountId!,
      amountMinor: _amount.minorUnits,
      counterAmountMinor: counterAmount,
      date: _date,
    );
    return true;
  }

  /// En una transferencia entre divisas hacen falta los dos importes: de ahí
  /// sale el tipo real que aplicó el banco, comisión incluida.
  Future<int?> _askCounterAmount(Currency currency) {
    final input = AmountInput();
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text('¿Cuánto entró en ${currency.code}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${input.display(currency.decimalDigits)} ${currency.symbol}',
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var d = 0; d <= 9; d++)
                    SizedBox(
                      width: 54,
                      child: FilledButton.tonal(
                        onPressed: () => setDialogState(() => input.pressDigit(d)),
                        child: Text('$d'),
                      ),
                    ),
                  SizedBox(
                    width: 54,
                    child: FilledButton.tonal(
                      onPressed: () => setDialogState(input.backspace),
                      child: const Text('⌫'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: input.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(input.minorUnits),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// La equivalencia en euros bajo el importe, en vivo.
class _EurEquivalent extends ConsumerWidget {
  final Money money;
  final String date;
  const _EurEquivalent({required this.money, required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = ref.watch(fxRepoProvider).rateFor(money.currency, date);
    return FutureBuilder<ResolvedRate>(
      future: future,
      builder: (_, snapshot) {
        final style = Theme.of(context).textTheme.bodySmall;
        if (!snapshot.hasData) {
          return Text(money.currency.code, style: style);
        }
        final resolved = snapshot.data!;
        final eur = resolved.rate.toEur(money);
        final suffix = resolved.isEstimated ? ' · tipo estimado' : '';
        return Text(
          '${money.currency.code} · ≈ ${formatMoney(eur)}$suffix',
          style: style,
        );
      },
    );
  }
}

class _NoAccountsYet extends StatelessWidget {
  const _NoAccountsYet();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.all(28),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Primero crea una cuenta',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text(
              'Abre la cartera arriba a la derecha y añade tu primera cuenta '
              'con su divisa.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/transactions/add_sheet.dart
git commit -m "feat: add bottom sheet for creating transactions"
```

---

## Task 21: Pantalla de cuentas

**Files:**
- Create: `lib/features/accounts/accounts_screen.dart`, `lib/features/accounts/new_account_dialog.dart`

- [ ] **Step 1: Escribir el diálogo de alta**

```dart
// lib/features/accounts/new_account_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/currency.dart';
import '../../data/db/tables.dart';

class NewAccountDialog extends ConsumerStatefulWidget {
  const NewAccountDialog({super.key});

  @override
  ConsumerState<NewAccountDialog> createState() => _NewAccountDialogState();
}

class _NewAccountDialogState extends ConsumerState<NewAccountDialog> {
  final _name = TextEditingController();
  final _institution = TextEditingController();
  Currency _currency = Currency.eur;
  AccountType _type = AccountType.checking;

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva cuenta'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _institution,
              decoration: const InputDecoration(
                labelText: 'Banco',
                hintText: 'Revolut, BBVA, Barclays…',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nombre de la cuenta',
                hintText: 'Libras, Cuenta corriente, Visa…',
              ),
            ),
            const SizedBox(height: 16),
            const Text('Divisa'),
            const SizedBox(height: 6),
            SegmentedButton<Currency>(
              segments: [
                for (final c in Currency.all)
                  ButtonSegment(value: c, label: Text('${c.code} ${c.symbol}')),
              ],
              selected: {_currency},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _currency = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              'La divisa no se puede cambiar una vez la cuenta tenga movimientos.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            const Text('Tipo'),
            const SizedBox(height: 6),
            DropdownButton<AccountType>(
              value: _type,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: AccountType.checking, child: Text('Cuenta corriente')),
                DropdownMenuItem(value: AccountType.savings, child: Text('Ahorro')),
                DropdownMenuItem(value: AccountType.cash, child: Text('Efectivo')),
                DropdownMenuItem(value: AccountType.creditCard, child: Text('Tarjeta de crédito')),
              ],
              onChanged: (v) => setState(() => _type = v ?? AccountType.checking),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Crear')),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    final repo = ref.read(accountRepoProvider);
    final institutionName = _institution.text.trim();
    int? institutionId;
    if (institutionName.isNotEmpty) {
      institutionId = await repo.createInstitution(name: institutionName);
    }
    await repo.create(
      name: name,
      currency: _currency,
      type: _type,
      institutionId: institutionId,
    );
    if (mounted) Navigator.of(context).pop();
  }
}
```

- [ ] **Step 2: Escribir la pantalla**

```dart
// lib/features/accounts/accounts_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/currency.dart';
import '../../core/formatting.dart';
import '../../core/money.dart';
import '../../data/repositories/account_repository.dart';
import 'new_account_dialog.dart';

final _groupsProvider = FutureProvider<List<AccountGroup>>((ref) async {
  ref.watch(accountsProvider); // recarga al crear o archivar
  return ref.watch(accountRepoProvider).groupedByInstitution();
});

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(_groupsProvider);
    final balances = ref.watch(balancesProvider).value ?? const <int, Money>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas')),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Todavía no tienes cuentas.\nToca + para crear la primera.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              for (final group in list) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                  child: Text(
                    group.institution?.name ?? 'Sin banco',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                for (final account in group.accounts)
                  ListTile(
                    title: Text(account.name),
                    subtitle: Text(account.currency),
                    trailing: Text(
                      formatMoney(balances[account.id] ??
                          Money.zero(Currency.byCode(account.currency))),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onLongPress: () => _confirmArchive(context, ref, account.id, account.name),
                  ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const NewAccountDialog(),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _confirmArchive(
      BuildContext context, WidgetRef ref, int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Archivar «$name»?'),
        content: const Text(
          'Desaparecerá de las listas, pero sus movimientos se conservan y '
          'siguen contando en tu histórico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(accountRepoProvider).archive(id);
      ref.invalidate(_groupsProvider);
    }
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/accounts/
git commit -m "feat: add accounts screen grouped by institution"
```

---

## Task 22: Editar y borrar un movimiento

**Files:**
- Create: `lib/features/transactions/edit_screen.dart`
- Modify: `lib/data/repositories/transaction_repository.dart`

- [ ] **Step 1: Añadir la actualización al repositorio**

Añade dentro de `class TransactionRepository`:

```dart
  /// Actualiza los campos editables. El importe y la fecha vuelven a calcular
  /// el tipo de cambio congelado, porque un movimiento de otro día vale otra
  /// cosa en euros.
  Future<void> update(
    int id, {
    required int amountMinor,
    required int? categoryId,
    required String date,
    String? merchant,
    String? note,
  }) async {
    _requirePositive(amountMinor);
    final existing = await byId(id);
    final currency = Currency.byCode(existing.currency);
    final resolved = await fx.rateFor(currency, date);
    final eur = resolved.rate.toEur(Money(amountMinor, currency));

    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        amountMinor: Value(amountMinor),
        fxRateToEurScaled: Value(resolved.rate.scaled),
        amountEurMinor: Value(eur.minorUnits),
        fxIsEstimated: Value(resolved.isEstimated),
        date: Value(date),
        categoryId: Value(categoryId),
        merchant: Value(merchant),
        note: Value(note),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
```

- [ ] **Step 2: Escribir la pantalla de edición**

```dart
// lib/features/transactions/edit_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/civil_date.dart';
import '../../core/currency.dart';
import '../../core/formatting.dart';
import '../../core/money.dart';
import '../../data/db/database.dart';
import '../../data/db/tables.dart';

class EditTransactionScreen extends ConsumerStatefulWidget {
  final int txId;
  const EditTransactionScreen({super.key, required this.txId});

  @override
  ConsumerState<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends ConsumerState<EditTransactionScreen> {
  Txn? _tx;
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  final _note = TextEditingController();
  int? _categoryId;
  String _date = todayCivil();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tx = await ref.read(transactionRepoProvider).byId(widget.txId);
    final currency = Currency.byCode(tx.currency);
    setState(() {
      _tx = tx;
      _amount.text =
          (tx.amountMinor / currency.minorUnitsPerUnit).toStringAsFixed(currency.decimalDigits);
      _merchant.text = tx.merchant ?? '';
      _note.text = tx.note ?? '';
      _categoryId = tx.categoryId;
      _date = tx.date;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tx = _tx;
    if (tx == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final currency = Currency.byCode(tx.currency);
    final isTransfer = tx.type == TxType.transfer;
    final kind = tx.type == TxType.income ? CategoryKind.income : CategoryKind.expense;
    final categories = (ref.watch(categoriesProvider).value ?? const <Category>[])
        .where((c) => c.kind == kind)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimiento'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Importe',
              suffixText: currency.symbol,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fecha'),
            trailing: Text(_date),
            onTap: _pickDate,
          ),
          if (!isTransfer) ...[
            const SizedBox(height: 8),
            const Text('Categoría'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in categories)
                  ChoiceChip(
                    label: Text('${c.icon} ${c.name}'),
                    selected: c.id == _categoryId,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _merchant,
            decoration: const InputDecoration(labelText: 'Comercio'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Nota'),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'Guardado en euros: ${formatMoney(Money(tx.amountEurMinor, Currency.eur))}'
            '${tx.fxIsEstimated ? ' (tipo estimado)' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Guardar cambios')),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseCivilDate(_date),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = civilDateOf(picked));
  }

  Future<void> _save() async {
    final tx = _tx!;
    final currency = Currency.byCode(tx.currency);
    final parsed = double.tryParse(_amount.text.replaceAll(',', '.'));
    final messenger = ScaffoldMessenger.of(context);
    if (parsed == null || parsed <= 0) {
      messenger.showSnackBar(const SnackBar(content: Text('Importe inválido')));
      return;
    }

    final navigator = Navigator.of(context);
    await ref.read(transactionRepoProvider).update(
          tx.id,
          amountMinor: (parsed * currency.minorUnitsPerUnit).round(),
          categoryId: _categoryId,
          date: _date,
          merchant: _merchant.text.trim().isEmpty ? null : _merchant.text.trim(),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        );
    navigator.pop();
  }

  /// Borra con opción de deshacer: reinsertamos los mismos datos si el usuario
  /// se arrepiente antes de que desaparezca el aviso.
  Future<void> _delete() async {
    final tx = _tx!;
    final repo = ref.read(transactionRepoProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    await repo.delete(tx.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Movimiento borrado'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => repo.restore(tx),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Añadir `restore` al repositorio**

Añade dentro de `class TransactionRepository`:

```dart
  /// Vuelve a insertar un movimiento borrado, con su id original.
  Future<void> restore(Txn tx) =>
      db.into(db.transactions).insert(tx, mode: InsertMode.insertOrReplace);
```

- [ ] **Step 4: Verificar que todo compila y pasa**

```bash
flutter analyze
flutter test
```

Expected: `No issues found!` y todas las pruebas en verde.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: edit and delete transactions with undo"
```

---

## Task 23: Pantalla de inicio

**Files:**
- Create: `lib/features/home/home_screen.dart`, `lib/features/home/transaction_tile.dart`
- Modify: `lib/app/app.dart`

- [ ] **Step 1: Escribir la fila de un movimiento**

```dart
// lib/features/home/transaction_tile.dart
import 'package:flutter/material.dart';
import '../../core/currency.dart';
import '../../core/formatting.dart';
import '../../core/money.dart';
import '../../data/db/database.dart';
import '../../data/db/tables.dart';

class TransactionTile extends StatelessWidget {
  final Txn tx;
  final String accountName;
  final String? categoryName;
  final String categoryIcon;
  final VoidCallback onTap;

  const TransactionTile({
    super.key,
    required this.tx,
    required this.accountName,
    required this.categoryName,
    required this.categoryIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final money = Money(tx.amountMinor, Currency.byCode(tx.currency));
    final isExpense = tx.type == TxType.expense;
    final isTransfer = tx.type == TxType.transfer;

    final color = isTransfer
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : isExpense
            ? const Color(0xFFE8422F)
            : const Color(0xFF12A150);

    return ListTile(
      onTap: onTap,
      leading: Text(
        isTransfer ? '🔄' : categoryIcon,
        style: const TextStyle(fontSize: 22),
      ),
      title: Text(tx.merchant ?? categoryName ?? 'Transferencia'),
      subtitle: Row(
        children: [
          Flexible(child: Text(accountName, overflow: TextOverflow.ellipsis)),
          if (tx.fxIsEstimated) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Tipo de cambio estimado',
              child: Icon(Icons.schedule,
                  size: 13, color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ],
      ),
      trailing: Text(
        isTransfer
            ? formatMoney(money)
            : formatSigned(money, negate: isExpense),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
```

- [ ] **Step 2: Escribir la pantalla**

```dart
// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/formatting.dart';
import '../accounts/accounts_screen.dart';
import '../transactions/add_sheet.dart';
import '../transactions/edit_screen.dart';
import 'transaction_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(monthTransactionsProvider);
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider);
    final netWorth = ref.watch(netWorthProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Este mes'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: netWorth.when(
                data: (m) => Text(formatMoney(m),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                loading: () => const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                error: (_, __) => const Text('—'),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountsScreen()),
            ),
          ),
        ],
      ),
      body: transactions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Todavía no hay movimientos este mes.\nToca + para añadir el primero.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final accountsById = {
            for (final a in accounts.value ?? []) a.id: a,
          };
          final categoriesById = {
            for (final c in categories.value ?? []) c.id: c,
          };
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final tx = list[i];
              final category = categoriesById[tx.categoryId];
              return TransactionTile(
                tx: tx,
                accountName: accountsById[tx.accountId]?.name ?? '—',
                categoryName: category?.name,
                categoryIcon: category?.icon ?? '🏷️',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EditTransactionScreen(txId: tx.id)),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

- [ ] **Step 3: Enganchar la pantalla a la app**

En `lib/app/app.dart`, sustituye el marcador de posición por la pantalla real:

```dart
import '../features/home/home_screen.dart';
```

y en el `MaterialApp`:

```dart
      home: const HomeScreen(),
```

Borra la clase `_Placeholder` del final del archivo.

- [ ] **Step 4: Verificar**

```bash
flutter analyze
flutter test
```

Expected: `No issues found!` y todas las pruebas en verde.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add home screen with month list and net worth"
```

---

## Task 24: Ejecutar en el emulador y verificación manual

**Files:** ninguno

- [ ] **Step 1: Arrancar el emulador**

```bash
flutter emulators --launch Medium_Phone_API_36.1
```

Espera a que aparezca la pantalla de inicio de Android.

- [ ] **Step 2: Instalar y ejecutar la app**

```bash
flutter run -d emulator-5554
```

Expected: la app arranca y muestra «Todavía no hay movimientos este mes».

- [ ] **Step 3: Recorrer el guion de verificación**

Comprueba una a una:

1. Crear institución **Revolut** con cuenta **Libras / GBP**.
2. Crear, bajo Revolut, la cuenta **Euros / EUR**.
3. Crear **BBVA / Cuenta corriente / EUR** y **Barclays / Cuenta corriente / GBP**.
4. Añadir un gasto de **24,50** en *Revolut Libras*, categoría Restaurantes. El importe debe mostrar **£** y la equivalencia en euros debajo.
5. Cambiar el chip a *BBVA* — el símbolo debe pasar a **€** y desaparecer la equivalencia.
6. Guardar. El movimiento aparece en la lista con el importe en su divisa nativa y el patrimonio de la barra superior se actualiza.
7. Añadir un **ingreso**. Comprobar que las categorías cambian a las de ingreso.
8. Hacer una **transferencia** de *Barclays* (GBP) a *BBVA* (EUR): debe pedir el segundo importe.
9. Abrir el movimiento de la transferencia y comprobar que **no aparece** como gasto.
10. Borrar un movimiento y pulsar **Deshacer**: debe volver a la lista y el saldo recuperarse.
11. Activar el modo avión y añadir un gasto en GBP: debe guardarse igualmente y mostrar el icono de tipo estimado.

- [ ] **Step 4: Anotar los fallos encontrados**

Si algo de los once puntos no se comporta como está descrito, arréglalo con una prueba que reproduzca el fallo primero. No pases al Plan 2 con puntos pendientes.

- [ ] **Step 5: Commit final de la fase**

```bash
git add -A
git commit -m "chore: verify phase 1 core on Android emulator"
git tag fase-1-nucleo
```

---

## Qué queda fuera de este plan

Cubierto por los planes siguientes, ya diseñado en la especificación:

- **Plan 2** — Gastos recurrentes (tablas `recurring_rules` y `recurring_skips`, `RecurringService`, pantalla «Próximos») e informes (gasto por categoría con gráfico, evolución del patrimonio).
- **Plan 3** — Importación CSV (tabla `import_batches`, mapeo de columnas, detección de duplicados, deshacer lote), copia de seguridad cifrada y **pantalla de Ajustes**, que es donde viven la copia de seguridad y la gestión de categorías e instituciones.

Consecuencia de dejar Ajustes para el Plan 3: en la Fase 1 se trabaja con las trece categorías sembradas en la tarea 9. `CategoryRepository.create` y `archive` ya existen y están probados, pero sin pantalla que los invoque. Si durante el uso real echas en falta una categoría concreta, es señal de que la pantalla debe adelantarse al Plan 2.

Las columnas `recurringRuleId`, `importBatchId` y `dedupeHash` ya existen en `transactions` desde la tarea 8, de modo que ninguno de los dos planes siguientes necesita migrar datos.

**Nota para el Plan 2:** será el primero que suba `schemaVersion` a 2. Ahí es donde toca implementar la copia automática previa a la migración que pide la especificación; en la Fase 1 no aplica, porque solo existe la creación inicial del esquema.
