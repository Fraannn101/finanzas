import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/db/tables.dart';
import 'package:finanzas/data/repositories/account_repository.dart';
import 'package:finanzas/data/repositories/category_repository.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;
  late AccountRepository accounts;
  late int cuenta;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CategoryRepository(db);
    accounts = AccountRepository(db);
    cuenta = await accounts.create(
      name: 'BBVA',
      currency: Currency.eur,
      type: AccountType.checking,
    );
  });
  tearDown(() => db.close());

  test('las categorías sembradas se separan por tipo', () async {
    final gastos = await repo.ofKind(CategoryKind.expense);
    final ingresos = await repo.ofKind(CategoryKind.income);
    expect(gastos.length, 9);
    expect(ingresos.length, 4);
    expect(gastos.map((c) => c.name), contains('Restaurantes'));
  });

  test('archivar una categoría la saca de las listas', () async {
    final id = (await repo.ofKind(CategoryKind.expense)).first.id;
    await repo.archive(id);
    expect((await repo.ofKind(CategoryKind.expense)).map((c) => c.id),
        isNot(contains(id)));
  });

  test('ordena por uso real dentro de su tipo', () async {
    final todas = await repo.ofKind(CategoryKind.expense);
    final poco = todas.first.id;
    final mucho = todas.last.id; // la última por sortOrder

    for (var i = 0; i < 3; i++) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            type: TxType.expense,
            accountId: cuenta,
            amountMinor: 100,
            currency: 'EUR',
            fxRateToEurScaled: 100000000,
            amountEurMinor: 100,
            date: '2026-09-12',
            categoryId: Value(mucho),
          ));
    }

    final orden = await repo.watchMostUsed(CategoryKind.expense).first;
    expect(orden.first.id, mucho);
    expect(orden.map((c) => c.id), contains(poco));
  });

  test('no mezcla categorías de ingreso en la lista de gasto', () async {
    final orden = await repo.watchMostUsed(CategoryKind.income).first;
    expect(orden.every((c) => c.kind == CategoryKind.income), isTrue);
    expect(orden.length, 4);
  });

  test('crear una categoría la añade a su tipo', () async {
    await repo.create(name: 'Mascotas', kind: CategoryKind.expense, icon: '🐕');
    final gastos = await repo.ofKind(CategoryKind.expense);
    expect(gastos.map((c) => c.name), contains('Mascotas'));
  });
}
