import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/data/backup/backup_crypto.dart';

/// Archivo congelado: `{"nota":"Café €"}` cifrado con la contraseña
/// `clavefija`. No regenerar: su valor es precisamente no cambiar.
const _vectorConocido = <int>[
  70, 73, 78, 65, 78, 90, 65, 83, 1, 150, 19, 112,
  41, 43, 96, 53, 216, 210, 143, 210, 124, 167, 110, 223,
  153, 108, 201, 23, 130, 82, 79, 60, 33, 132, 214, 221,
  159, 113, 57, 38, 42, 164, 166, 132, 62, 91, 254, 137,
  186, 179, 132, 140, 197, 100, 104, 244, 242, 117, 30, 160,
  54, 192, 180, 116, 55, 41, 245, 96, 41, 62, 100, 168,
  85,
];

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

  test('un byte alterado del texto cifrado rompe el descifrado', () async {
    // El byte 37 es el primero del cuerpo cifrado. Alterar los últimos 16
    // tocaría la etiqueta de autenticación, no el texto: GCM detecta ambos,
    // pero entonces el texto cifrado en sí no lo probaría nadie.
    final bytes = await BackupCrypto.encrypt('{"importe":2450}', clave);
    bytes[37] ^= 0xFF;
    expect(
      () => BackupCrypto.decrypt(bytes, clave),
      throwsA(isA<BackupPasswordError>()),
    );
  });

  test('una etiqueta alterada rompe el descifrado', () async {
    final bytes = await BackupCrypto.encrypt('{"importe":2450}', clave);
    bytes[bytes.length - 3] ^= 0xFF;
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

  test('manipular el byte de versión rompe el descifrado', () async {
    // La cabecera va en claro, pero firmada como AAD. Sin eso, este byte
    // sería libre de cambiar: el descifrado funcionaría igual y el archivo
    // mentiría sobre su propia versión.
    //
    // Se baja a 0 en vez de subirlo: una versión mayor la pararía antes la
    // comprobación de formato, y entonces esta prueba no estaría ejercitando
    // el AAD, que es lo que viene a comprobar.
    final bytes = await BackupCrypto.encrypt('{"importe":2450}', clave);
    bytes[8] = 0;
    expect(
      () => BackupCrypto.decrypt(bytes, clave),
      throwsA(isA<BackupPasswordError>()),
    );
  });

  test('los acentos y símbolos sobreviven', () async {
    // Una app española donde las categorías llevan «Café», «Ñoño» y «€».
    // Sin esta prueba, truncar a Latin-1 en vez de codificar a UTF-8 pasaría
    // inadvertido y corrompería los datos al exportar.
    const texto = '{"cat":"Café ñ €","nota":"más de 3 €"}';
    final bytes = await BackupCrypto.encrypt(texto, clave);
    expect(await BackupCrypto.decrypt(bytes, clave), texto);
  });

  test('decrypt rechaza un archivo corto', () async {
    final corto = Uint8List.fromList(utf8.encode('FINANZAS') + [1, 2, 3]);
    expect(
      () => BackupCrypto.decrypt(corto, clave),
      throwsA(isA<BackupFormatError>()),
    );
  });

  test('decrypt rechaza un archivo ajeno', () async {
    final ajeno = Uint8List.fromList(
        utf8.encode('OTRA COSA que mide lo suficiente para pasar el largo...'));
    expect(
      () => BackupCrypto.decrypt(ajeno, clave),
      throwsA(isA<BackupFormatError>()),
    );
  });

  test('decrypt rechaza una versión que no entiende', () async {
    // Un archivo legítimo de una versión futura daría «contraseña incorrecta»
    // si solo lo detectara GCM, que es justo el mensaje equivocado.
    final bytes = await BackupCrypto.encrypt('{}', clave);
    bytes[8] = 99;
    expect(
      () => BackupCrypto.decrypt(bytes, clave),
      throwsA(isA<BackupFormatError>()),
    );
  });

  test('un archivo guardado antes sigue abriéndose', () async {
    // Vector de respuesta conocida. Es la única prueba capaz de detectar que
    // alguien cambie las iteraciones, el orden de los campos, la posición de
    // la etiqueta o el AAD: todo eso pasa desapercibido comparando una
    // exportación con su propia importación. Aquí hay un archivo congelado.
    final archivo = Uint8List.fromList(_vectorConocido);
    expect(await BackupCrypto.decrypt(archivo, 'clavefija'), '{"nota":"Café €"}');
  });
}
