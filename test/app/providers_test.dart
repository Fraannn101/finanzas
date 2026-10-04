import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/app/providers.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/money.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/db/tables.dart';
import 'package:finanzas/data/repositories/account_repository.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [dbProvider.overrideWithValue(db)]);
  });
  tearDown(() {
    container.dispose();
    db.close();
  });

  test('el patrimonio se resuelve en una lectura en frío', () async {
    // Leer este provider el primero, sin que nada haya tocado antes los
    // saldos, es exactamente lo que hace la pantalla de inicio al abrirse.
    // Si solo se observaran los saldos en vez de esperarlos, su primera
    // emisión reconstruiría el provider a mitad del `await` y la cifra se
    // quedaría cargando para siempre.
    final total = await container
        .read(netWorthProvider.future)
        .timeout(const Duration(seconds: 20));
    expect(total, Money.zero(Currency.eur));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('el patrimonio en frío suma las cuentas que ya existen', () async {
    await AccountRepository(db).create(
      name: 'BBVA',
      currency: Currency.eur,
      type: AccountType.checking,
      initialBalanceMinor: 320455,
    );
    final total = await container
        .read(netWorthProvider.future)
        .timeout(const Duration(seconds: 20));
    expect(total, const Money(320455, Currency.eur));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
