// test/data/backup_service_test.dart
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
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

  test('el archivo lleva las dos versiones y la fecha', () async {
    final bytes = await service.export(clave);
    final json = jsonDecode(await BackupCrypto.decrypt(bytes, clave))
        as Map<String, dynamic>;
    expect(json['formato'], BackupCrypto.formatVersion);
    expect(json['esquema'], db.schemaVersion);
    expect(json['exportado'], isA<String>());
  });

  test('cuenta lo que ha guardado', () async {
    await accounts.create(
      name: 'BBVA',
      currency: Currency.eur,
      type: AccountType.checking,
    );
    final bytes = await service.export(clave);
    final resumen = await service.summarize(bytes, clave);
    expect(resumen.cuentas, 1);
    expect(resumen.movimientos, 0);
  });

  test('exportar registra la fecha de la última copia', () async {
    expect(await service.lastBackupDate(), isNull);
    await service.export(clave);
    expect(await service.lastBackupDate(), isNotNull);
  });

  test('un formato futuro se rechaza antes de pedir nada', () async {
    final bytes = await service.export(clave);
    bytes[8] = 99;
    expect(
      () => service.summarize(bytes, clave),
      throwsA(isA<BackupTooNewError>()),
    );
  });

  test('una cabecera manipulada se detecta', () async {
    final bytes = await service.export(clave);
    bytes[8] = 0; // formato menor: pasa el filtro de «demasiado nuevo»
    // La cabecera va firmada como AAD, así que el descifrado falla antes de
    // llegar al contraste contra el JSON. Ese contraste sigue existiendo como
    // segunda red, pero esta es la que salta primero.
    expect(
      () => service.summarize(bytes, clave),
      throwsA(isA<BackupPasswordError>()),
    );
  });

  test('la fecha de la última copia no se exporta', () async {
    await service.export(clave); // registra ultima_copia
    final bytes = await service.export(clave);
    final json = jsonDecode(await BackupCrypto.decrypt(bytes, clave))
        as Map<String, dynamic>;
    final claves =
        (json['app_settings'] as List).map((f) => (f as Map)['key']);
    expect(claves, isNot(contains('ultima_copia')));
  });
}
