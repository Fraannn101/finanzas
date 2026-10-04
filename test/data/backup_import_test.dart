// test/data/backup_import_test.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/money.dart';
import 'package:finanzas/data/backup/backup_crypto.dart';
import 'package:finanzas/data/backup/backup_service.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/db/tables.dart';
import 'package:finanzas/data/repositories/account_repository.dart';

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late BackupService service;
  const clave = 'mi contraseña';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    accounts = AccountRepository(db);
    service = BackupService(db);
  });
  tearDown(() => db.close());

  Future<int> cuenta(String nombre, Currency divisa, int saldo) =>
      accounts.create(
        name: nombre,
        currency: divisa,
        type: AccountType.checking,
        initialBalanceMinor: saldo,
      );

  test('importar sustituye por completo', () async {
    await cuenta('Original', Currency.eur, 100000);
    final copia = await service.export(clave);

    await cuenta('Posterior', Currency.gbp, 50000);
    expect((await accounts.activeAccounts()).length, 2);

    await service.import(copia, clave);
    final tras = await accounts.activeAccounts();
    expect(tras, hasLength(1));
    expect(tras.single.name, 'Original');
  });

  test('los saldos cuadran tras restaurar', () async {
    final id = await cuenta('BBVA', Currency.eur, 320455);
    final antes = await accounts.balanceOf(id);
    final copia = await service.export(clave);

    await db.customStatement('DELETE FROM accounts');
    await service.import(copia, clave);

    expect(await accounts.balanceOf(id), antes);
    expect(antes, const Money(320455, Currency.eur));
  });

  test('el rescate sobrevive a la importación', () async {
    await cuenta('Original', Currency.eur, 100000);
    final copia = await service.export(clave);
    await cuenta('Posterior', Currency.gbp, 50000);

    await service.import(copia, clave);

    // El archivo importado traía su propio app_settings. Si el rescate se
    // tomara de ahí, aquí no habría nada y «Deshacer» no funcionaría.
    expect(await service.hasRescue(), isTrue);
  });

  test('deshacer devuelve lo que había antes de importar', () async {
    await cuenta('Original', Currency.eur, 100000);
    final copia = await service.export(clave);
    await cuenta('Posterior', Currency.gbp, 50000);

    await service.import(copia, clave);
    expect((await accounts.activeAccounts()).length, 1);

    await service.undoImport();
    final tras = await accounts.activeAccounts();
    expect(tras, hasLength(2));
    expect(tras.map((a) => a.name), containsAll(['Original', 'Posterior']));
  });

  test('una contraseña incorrecta no toca la base de datos', () async {
    await cuenta('Original', Currency.eur, 100000);
    final copia = await service.export(clave);

    await expectLater(
      service.import(copia, 'otra cosa'),
      throwsA(isA<BackupPasswordError>()),
    );
    expect((await accounts.activeAccounts()).single.name, 'Original');
  });

  test('una copia de un esquema anterior se importa', () async {
    await cuenta('Original', Currency.eur, 100000);
    final copia = await service.export(clave);
    // Se simula una copia hecha cuando el esquema era 0.
    final json = await BackupCrypto.decrypt(copia, clave);
    final vieja = await BackupCrypto.encrypt(
        json.replaceFirst('"esquema":1', '"esquema":0'), clave);

    await service.import(vieja, clave); // no lanza
    expect((await accounts.activeAccounts()).single.name, 'Original');
  });

  /// Una copia cuya primera categoría cuelga de [padre], tomando el resto del
  /// estado actual.
  Future<Uint8List> copiaConPadre(int padre) async {
    final copia = await service.export(clave);
    final json = jsonDecode(await BackupCrypto.decrypt(copia, clave))
        as Map<String, dynamic>;
    ((json['categories'] as List).first as Map)['parent_id'] = padre;
    return BackupCrypto.encrypt(jsonEncode(json), clave);
  }

  test('una categoría hija con id menor que su padre se importa', () async {
    // El hijo (id 1) sale del volcado antes que su padre (id 2). Con las
    // claves foráneas comprobadas fila a fila, la inserción fallaría.
    final copia = await copiaConPadre(2);
    await service.import(copia, clave); // no lanza
    final cats = await db.select(db.categories).get();
    expect(cats.firstWhere((c) => c.id == 1).parentId, 2);
  });

  test('un padre inexistente sigue rechazándose y no deja rastro', () async {
    await cuenta('Original', Currency.eur, 100000);
    final copia = await copiaConPadre(9999);

    // Diferir la comprobación no la desactiva: salta al confirmar, y la
    // transacción entera se deshace.
    await expectLater(service.import(copia, clave), throwsA(isA<Exception>()));
    expect((await accounts.activeAccounts()).single.name, 'Original');
    expect((await db.select(db.categories).get()), hasLength(13));
  });
}
