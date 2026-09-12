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

  static void _requirePositive(int amountMinor) {
    if (amountMinor <= 0) {
      throw ArgumentError('El importe debe ser mayor que cero: $amountMinor');
    }
  }
}
