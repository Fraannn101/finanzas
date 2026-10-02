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

  test('el importe recibido tampoco puede ser cero', () async {
    // El CHECK de SQLite solo prohíbe los negativos, así que sin esta
    // comprobación una transferencia sacaría dinero del origen y no metería
    // nada en el destino, sin que fallara nada.
    expect(
      () => repo.addTransfer(
        fromAccountId: barclays,
        toAccountId: bbva,
        amountMinor: 85000,
        counterAmountMinor: 0,
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
