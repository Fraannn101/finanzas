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

  /// Vuelve a insertar un movimiento borrado, con su id original.
  Future<void> restore(Txn tx) =>
      db.into(db.transactions).insert(tx, mode: InsertMode.insertOrReplace);

  /// Rehace la conversión a euros de los movimientos que se guardaron con un
  /// tipo prestado de otro día, ahora que puede haber llegado el de verdad.
  ///
  /// Sin esto, la especificación promete algo que nadie cumple: un gasto
  /// apuntado sin cobertura se quedaría marcado como estimado para siempre,
  /// aunque el tipo correcto se descargue cinco minutos después. Se llama
  /// después de cada descarga que haya ido bien.
  Future<int> recomputeEstimated() async {
    final pending = await (db.select(db.transactions)
          ..where((t) => t.fxIsEstimated.equals(true)))
        .get();

    var fixed = 0;
    for (final tx in pending) {
      final currency = Currency.byCode(tx.currency);
      final ResolvedRate resolved;
      try {
        resolved = await fx.rateFor(currency, tx.date);
      } on NoFxRateAvailable {
        continue; // sigue sin haber nada mejor
      }
      if (resolved.isEstimated) continue; // el tipo real aún no ha llegado

      final eur = resolved.rate.toEur(Money(tx.amountMinor, currency));
      await (db.update(db.transactions)..where((t) => t.id.equals(tx.id)))
          .write(TransactionsCompanion(
        fxRateToEurScaled: Value(resolved.rate.scaled),
        amountEurMinor: Value(eur.minorUnits),
        fxIsEstimated: const Value(false),
        updatedAt: Value(DateTime.now()),
      ));
      fixed++;
    }
    return fixed;
  }

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

  static void _requirePositive(int amountMinor) {
    if (amountMinor <= 0) {
      throw ArgumentError('El importe debe ser mayor que cero: $amountMinor');
    }
  }
}
