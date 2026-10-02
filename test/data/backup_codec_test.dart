// test/data/backup_codec_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/data/backup/backup_codec.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/db/tables.dart';
import 'package:finanzas/data/repositories/account_repository.dart';

void main() {
  late AppDatabase db;
  late AccountRepository accounts;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    accounts = AccountRepository(db);
  });
  tearDown(() => db.close());

  test('vuelca las seis tablas', () async {
    final dump = await BackupCodec.dump(db);
    expect(dump.keys, containsAll(BackupCodec.tableNames));
    expect(dump['categories'], hasLength(13)); // las sembradas
  });

  test('los importes siguen siendo enteros', () async {
    final id = await accounts.create(
      name: 'BBVA',
      currency: Currency.eur,
      type: AccountType.checking,
      initialBalanceMinor: 320455,
    );
    final dump = await BackupCodec.dump(db);
    final fila = dump['accounts']!.firstWhere((f) => f['id'] == id);
    expect(fila['initial_balance_minor'], 320455);
    expect(fila['initial_balance_minor'], isA<int>());
  });

  test('las enumeraciones se guardan como texto, no como índice', () async {
    await accounts.create(
      name: 'Visa',
      currency: Currency.eur,
      type: AccountType.creditCard,
    );
    final dump = await BackupCodec.dump(db);
    final fila = dump['accounts']!.last;
    expect(fila['type'], 'creditCard');
  });

  test('las claves locales no se exportan', () async {
    await db.into(db.appSettings).insert(
        AppSettingsCompanion.insert(key: 'rescate', value: '{...}'));
    await db.into(db.appSettings).insert(
        AppSettingsCompanion.insert(key: 'tema', value: 'oscuro'));

    final dump = await BackupCodec.dump(db);
    final claves = dump['app_settings']!.map((f) => f['key']);
    expect(claves, contains('tema'));
    expect(claves, isNot(contains('rescate')));
  });

  test('restaurar vacía y repuebla', () async {
    await accounts.create(
      name: 'Original',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    final dump = await BackupCodec.dump(db);

    await accounts.create(
      name: 'Posterior',
      currency: Currency.gbp,
      type: AccountType.checking,
    );
    expect((await db.select(db.accounts).get()).length, 2);

    await BackupCodec.restore(db, dump);
    final restauradas = await db.select(db.accounts).get();
    expect(restauradas, hasLength(1));
    expect(restauradas.single.name, 'Original');
  });

  test('restaurar respeta las claves foráneas', () async {
    final inst = await accounts.createInstitution(name: 'Revolut');
    await accounts.create(
      name: 'Libras',
      currency: Currency.gbp,
      type: AccountType.checking,
      institutionId: inst,
    );
    final dump = await BackupCodec.dump(db);
    await BackupCodec.restore(db, dump); // no lanza
    expect((await db.select(db.accounts).get()).single.institutionId, inst);
  });

  test('los acentos sobreviven al volcado', () async {
    await accounts.create(
      name: 'Café Ñoño €',
      currency: Currency.eur,
      type: AccountType.cash,
    );
    final dump = await BackupCodec.dump(db);
    await BackupCodec.restore(db, dump);
    expect((await db.select(db.accounts).get()).single.name, 'Café Ñoño €');
  });
}
