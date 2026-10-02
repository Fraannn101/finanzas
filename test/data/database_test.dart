// test/data/database_test.dart
import 'package:drift/drift.dart';
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
