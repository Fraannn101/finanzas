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
