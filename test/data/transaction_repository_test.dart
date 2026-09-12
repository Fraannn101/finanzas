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
    await fx.save('2026-09-10', const FxRate(Currency.gbp, 117234500), source: 'ecb');
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

  test('marca el movimiento cuando el tipo es de otro día laborable', () async {
    // El viernes 11 no tiene tipo propio: se usa el del jueves 10.
    final id = await repo.addExpense(
      accountId: revolutGbp,
      amountMinor: 1000,
      categoryId: comida,
      date: '2026-09-11',
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

  test('recalcula los movimientos guardados con un tipo prestado', () async {
    final id = await repo.addExpense(
      accountId: revolutGbp,
      amountMinor: 10000,
      categoryId: comida,
      date: '2026-09-11',
    );
    expect((await repo.byId(id)).fxIsEstimated, isTrue);

    await fx.save('2026-09-11', const FxRate(Currency.gbp, 120000000), source: 'ecb');
    expect(await repo.recomputeEstimated(), 1);

    final tx = await repo.byId(id);
    expect(tx.fxIsEstimated, isFalse);
    expect(tx.fxRateToEurScaled, 120000000);
    expect(tx.amountEurMinor, 12000); // 100,00 £ × 1,2
  });

  test('no toca los movimientos cuyo tipo real sigue sin llegar', () async {
    await repo.addExpense(
      accountId: revolutGbp,
      amountMinor: 10000,
      categoryId: comida,
      date: '2026-09-11',
    );
    expect(await repo.recomputeEstimated(), 0);
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
