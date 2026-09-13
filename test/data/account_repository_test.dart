import 'package:drift/drift.dart' show Value;
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
    expect(groups.length, 2);
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

  test('ordena por uso real, no por sortOrder', () async {
    final poco = await repo.create(
      name: 'Poco usada',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    final mucho = await repo.create(
      name: 'Muy usada',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    // Ambas tienen sortOrder 0: si el orden viniera de ahí, sería arbitrario.
    for (var i = 0; i < 3; i++) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            type: TxType.expense,
            accountId: mucho,
            amountMinor: 100,
            currency: 'EUR',
            fxRateToEurScaled: 100000000,
            amountEurMinor: 100,
            date: '2026-09-12',
          ));
    }
    // `since` explícito: si dependiera de la fecha de hoy, esta prueba
    // empezaría a fallar sola a los 90 días de escribirla.
    final orden = await repo.watchMostUsed(since: '2026-01-01').first;
    expect(orden.first.id, mucho);
    expect(orden.map((a) => a.id), contains(poco));
  });

  test('el uso reciente manda sobre el histórico', () async {
    final antigua = await repo.create(
      name: 'Efectivo',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    final actual = await repo.create(
      name: 'Revolut',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    Future<void> gasto(int cuenta, String fecha) =>
        db.into(db.transactions).insert(TransactionsCompanion.insert(
              type: TxType.expense,
              accountId: cuenta,
              amountMinor: 100,
              currency: 'EUR',
              fxRateToEurScaled: 100000000,
              amountEurMinor: 100,
              date: fecha,
            ));

    for (var i = 0; i < 10; i++) {
      await gasto(antigua, '2024-01-15'); // mucho, pero viejo
    }
    await gasto(actual, '2026-09-10'); // poco, pero reciente

    final orden = await repo.watchMostUsed(since: '2026-06-01').first;
    expect(orden.first.id, actual);
  });

  test('una transferencia cuenta para las dos cuentas', () async {
    final origen = await repo.create(
      name: 'Origen',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    final destino = await repo.create(
      name: 'Destino',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    final tercera = await repo.create(
      name: 'Sin usar',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          type: TxType.transfer,
          accountId: origen,
          amountMinor: 1000,
          currency: 'EUR',
          fxRateToEurScaled: 100000000,
          amountEurMinor: 1000,
          date: '2026-09-12',
          counterAccountId: Value(destino),
          counterAmountMinor: const Value(1000),
        ));

    final orden = await repo.watchMostUsed(since: '2026-01-01').first;
    // La transferencia sube a las dos, no solo al origen.
    expect(orden.map((a) => a.id).take(2), containsAll([origen, destino]));
    expect(orden.last.id, tercera);
  });

  test('encuentra un banco existente por su nombre', () async {
    final id = await repo.createInstitution(name: 'Revolut');
    expect(await repo.institutionByName('Revolut'), id);
    expect(await repo.institutionByName('Otro'), isNull);
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
