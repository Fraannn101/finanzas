import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/data/backup/backup_crypto.dart';

void main() {
  const clave = 'una contraseña larga';

  test('ida y vuelta devuelve el texto original', () async {
    final bytes = await BackupCrypto.encrypt('{"hola":1}', clave);
    expect(await BackupCrypto.decrypt(bytes, clave), '{"hola":1}');
  });

  test('la cabecera va en claro y es reconocible', () async {
    final bytes = await BackupCrypto.encrypt('{}', clave);
    expect(utf8.decode(bytes.sublist(0, 8)), 'FINANZAS');
    expect(bytes[8], BackupCrypto.formatVersion);
  });

  test('el formato se puede leer sin la contraseña', () async {
    final bytes = await BackupCrypto.encrypt('{}', clave);
    expect(BackupCrypto.readFormat(bytes), BackupCrypto.formatVersion);
  });

  test('una contraseña incorrecta falla', () async {
    final bytes = await BackupCrypto.encrypt('{}', clave);
    expect(
      () => BackupCrypto.decrypt(bytes, 'otra cosa'),
      throwsA(isA<BackupPasswordError>()),
    );
  });

  test('un byte alterado rompe el descifrado', () async {
    final bytes = await BackupCrypto.encrypt('{"importe":2450}', clave);
    bytes[bytes.length - 3] ^= 0xFF; // dentro del cuerpo cifrado
    expect(
      () => BackupCrypto.decrypt(bytes, clave),
      throwsA(isA<BackupPasswordError>()),
    );
  });

  test('un archivo que no es nuestro se rechaza antes de descifrar', () {
    final basura = Uint8List.fromList(utf8.encode('esto no es un backup xxxx'));
    expect(() => BackupCrypto.readFormat(basura), throwsA(isA<BackupFormatError>()));
  });

  test('un formato futuro se detecta sin contraseña', () async {
    final bytes = await BackupCrypto.encrypt('{}', clave);
    bytes[8] = 99;
    expect(BackupCrypto.readFormat(bytes), 99);
  });

  test('el salt cambia en cada archivo', () async {
    final a = await BackupCrypto.encrypt('{}', clave);
    final b = await BackupCrypto.encrypt('{}', clave);
    expect(a.sublist(9, 25), isNot(b.sublist(9, 25)));
  });
}
