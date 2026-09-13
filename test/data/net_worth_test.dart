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
    //   120500 × 1,172345 = 141267,5725 -> 141268 (el medio sube)
    //   190000 × 0,92234   = 175244,6    -> 175245
    // = 320455 + 141268 + 175245 = 636968 céntimos
    final total = await accounts.netWorthEur(fx, '2026-09-12');
    expect(total, const Money(636968, Currency.eur));
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
