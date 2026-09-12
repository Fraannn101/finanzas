import 'package:drift/drift.dart';
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

  test('un contra-importe en un gasto no suma a la otra cuenta', () async {
    // Fila corrupta: un gasto no debería llevar cuenta destino. El filtro
    // `AND t.type = 'transfer'` del segundo subconsulta existe justo para
    // ignorarla. Sin esta prueba, borrar ese filtro no rompe nada.
    final origen = await repo.create(
      name: 'Origen',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    final otra = await repo.create(
      name: 'Otra',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    await insertTx(
      type: TxType.expense,
      accountId: origen,
      amountMinor: 5000,
      currency: 'EUR',
      counterAccountId: otra,
      counterAmountMinor: 5000,
    );
    expect(await repo.balanceOf(otra), Money.zero(Currency.eur));
  });
}
