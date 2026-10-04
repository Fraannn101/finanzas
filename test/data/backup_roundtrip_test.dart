// test/data/backup_roundtrip_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/fx.dart';
import 'package:finanzas/data/backup/backup_codec.dart';
import 'package:finanzas/data/backup/backup_service.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/db/tables.dart';
import 'package:finanzas/data/repositories/account_repository.dart';
import 'package:finanzas/data/repositories/category_repository.dart';
import 'package:finanzas/data/repositories/fx_repository.dart';
import 'package:finanzas/data/repositories/transaction_repository.dart';

void main() {
  test('la ida y vuelta es exacta, fila a fila', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final accounts = AccountRepository(db);
    final fx = FxRepository(db);
    final categories = CategoryRepository(db);
    final tx = TransactionRepository(db, accounts, fx);
    final service = BackupService(db);
    const clave = 'contraseña de prueba';

    // Una base con algo de todo.
    await fx.save('2026-09-12', const FxRate(Currency.gbp, 117234500),
        source: 'ecb');
    await fx.save('2026-09-12', const FxRate(Currency.usd, 92234000),
        source: 'ecb');

    final revolut = await accounts.createInstitution(name: 'Revolut');
    final libras = await accounts.create(
      name: 'Libras',
      currency: Currency.gbp,
      type: AccountType.checking,
      institutionId: revolut,
      initialBalanceMinor: 120500,
    );
    final euros = await accounts.create(
      name: 'Café €',
      currency: Currency.eur,
      type: AccountType.checking,
      institutionId: revolut,
    );
    final visa = await accounts.create(
      name: 'Visa',
      currency: Currency.eur,
      type: AccountType.creditCard,
    );
    final archivada = await accounts.create(
      name: 'Vieja',
      currency: Currency.usd,
      type: AccountType.savings,
    );
    await accounts.archive(archivada);

    final comida = (await categories.ofKind(CategoryKind.expense)).first.id;
    await categories
        .archive((await categories.ofKind(CategoryKind.expense)).last.id);

    await tx.addExpense(
      accountId: libras,
      amountMinor: 2450,
      categoryId: comida,
      date: '2026-09-12',
      merchant: 'Pub',
      note: 'con acentos: ñ á €',
    );
    await tx.addIncome(
      accountId: euros,
      amountMinor: 240000,
      categoryId: null,
      date: '2026-09-12',
    );
    await tx.addTransfer(
      fromAccountId: libras,
      toAccountId: euros,
      amountMinor: 85000,
      counterAmountMinor: 99500,
      date: '2026-09-12',
    );
    await tx.addExpense(
      accountId: visa,
      amountMinor: 31240,
      categoryId: comida,
      date: '2026-09-12',
    );

    final antes = await BackupCodec.dump(db);
    final saldosAntes = {
      for (final a in await accounts.activeAccounts())
        a.id: await accounts.balanceOf(a.id)
    };
    final patrimonioAntes = await accounts.netWorthEur(fx, '2026-09-12');

    final copia = await service.export(clave);

    // Vaciar del todo y restaurar.
    for (final t in BackupCodec.tableNames.reversed) {
      await db.customStatement('DELETE FROM $t');
    }
    await service.import(copia, clave);

    final despues = await BackupCodec.dump(db);

    for (final tabla in BackupCodec.tableNames) {
      expect(despues[tabla], hasLength(antes[tabla]!.length),
          reason: 'la tabla $tabla cambió de tamaño');
      for (var i = 0; i < antes[tabla]!.length; i++) {
        expect(despues[tabla]![i], antes[tabla]![i],
            reason: 'la fila $i de $tabla no es idéntica');
      }
    }

    // La comprobación que de verdad detecta filas perdidas o duplicadas.
    for (final entry in saldosAntes.entries) {
      expect(await accounts.balanceOf(entry.key), entry.value,
          reason: 'el saldo de la cuenta ${entry.key} no cuadra');
    }
    expect(await accounts.netWorthEur(fx, '2026-09-12'), patrimonioAntes);
  });
}
