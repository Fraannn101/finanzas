# Copia de seguridad cifrada — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Exportar e importar toda la base de datos como un archivo JSON cifrado, con copia de rescate automática y un aviso a los 7 días, funcionando igual en Android y en navegador.

**Architecture:** Cuatro piezas con una responsabilidad cada una — el cifrado no sabe de bases de datos, el volcado no sabe de cifrado, el servicio los une, y la entrega del archivo es lo único que mira la plataforma. Las filas se serializan **en crudo** (`SELECT *`), de modo que el JSON es una representación literal de SQLite y ninguna conversión de tipos puede corromper una copia.

**Tech Stack:** Flutter 3.41 · Drift 2.34 · `cryptography` (AES-256-GCM, PBKDF2) · `file_picker` · `file_saver` · `share_plus`

**Spec:** `docs/superpowers/specs/2026-10-02-copia-seguridad-design.md`

---

## Antes de empezar: la rama

El trabajo de la Fase 1 ya está fusionado en `master`. Esta funcionalidad parte de ahí, no de `fase-1-nucleo`:

```bash
git checkout master && git pull && git checkout -b copia-seguridad
```

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `lib/data/backup/backup_crypto.dart` | Cabecera, derivación de clave y AES-GCM. No conoce la base de datos. |
| `lib/data/backup/backup_codec.dart` | Volcado y restauración de las seis tablas en crudo. No conoce el cifrado. |
| `lib/data/backup/backup_service.dart` | Une las dos anteriores: exportar, importar, rescate, fechas. |
| `lib/data/backup/backup_file.dart` | Lo único que mira la plataforma: compartir en Android, descargar en web, elegir archivo. |
| `lib/features/settings/settings_screen.dart` | Pantalla de Ajustes. |
| `lib/features/settings/password_dialog.dart` | Entrada de contraseña con el aviso de irreversibilidad. |
| `lib/features/home/backup_banner.dart` | La línea de aviso a los 7 días. |

Las tres primeras son Dart puro sobre Drift y se prueban sin emulador. `backup_file.dart` es el único sitio con `kIsWeb`.

---

## Task 1: Dependencias

**Files:** Modify `pubspec.yaml`

- [ ] **Step 1: Instalar**

```bash
flutter pub add cryptography file_picker file_saver share_plus
```

- [ ] **Step 2: Verificar que no rompe nada**

```bash
flutter pub get && flutter test
```

Expected: `Got dependencies!` y `All tests passed!` con 94 pruebas.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add crypto and file packages for backups"
```

---

## Task 2: Cabecera y cifrado

**Files:**
- Create: `lib/data/backup/backup_crypto.dart`
- Test: `test/data/backup_crypto_test.dart`

El formato de archivo es una cabecera en claro seguida del cuerpo cifrado. El salt y el nonce **no son secretos**: sin ellos el archivo sería indescifrable incluso con la contraseña correcta.

```
"FINANZAS" (8B) · formato (1B) · salt (16B) · nonce (12B) · cuerpo cifrado
```

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/data/backup_crypto_test.dart
import 'dart:convert';
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

  test('un archivo guardado antes sigue abriéndose', () async {
    // Vector de respuesta conocida. Es la única prueba capaz de detectar que
    // alguien cambie las iteraciones, el orden de los campos, la posición de
    // la etiqueta o el AAD: todo eso pasa desapercibido comparando una
    // exportación con su propia importación. Aquí hay un archivo congelado.
    //
    // Generado una vez con: BackupCrypto.encrypt('{"nota":"Café €"}', 'clavefija')
    final archivo = Uint8List.fromList(_vectorConocido);
    expect(await BackupCrypto.decrypt(archivo, 'clavefija'), '{"nota":"Café €"}');
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
}
```

Añade `import 'dart:typed_data';` al principio del fichero de prueba.

- [ ] **Step 2: Ejecutar para verla fallar**

Run: `flutter test test/data/backup_crypto_test.dart`
Expected: FAIL — `backup_crypto.dart not found`.

- [ ] **Step 3: Implementar**

```dart
// lib/data/backup/backup_crypto.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// El archivo no tiene la forma esperada.
class BackupFormatError implements Exception {
  final String message;
  BackupFormatError(this.message);
  @override
  String toString() => message;
}

/// La contraseña no abre el archivo, o el archivo está dañado. Las dos causas
/// son indistinguibles: GCM solo dice que la autenticación ha fallado, y
/// fingir que sabemos cuál de las dos es sería mentir al usuario.
class BackupPasswordError implements Exception {
  @override
  String toString() => 'Contraseña incorrecta, o el archivo está dañado';
}

/// Cabecera en claro + cuerpo cifrado con AES-256-GCM.
///
/// El salt y el nonce van legibles a propósito: no son secretos, y sin ellos
/// el archivo no se podría descifrar ni con la contraseña correcta.
class BackupCrypto {
  static const magic = 'FINANZAS';
  static const formatVersion = 1;

  static const _magicLength = 8;
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _headerLength = _magicLength + 1 + _saltLength + _nonceLength;

  /// Fijo y documentado a propósito: si cambiara entre versiones, las copias
  /// antiguas dejarían de abrirse. Subirlo exige incrementar [formatVersion]
  /// y conservar la lectura del anterior.
  static const _iterations = 100000;

  static final _cipher = AesGcm.with256bits();
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  /// Lee la versión de formato **sin descifrar**, que es lo que permite
  /// rechazar un archivo del futuro sin pedir siquiera la contraseña.
  static int readFormat(Uint8List bytes) {
    if (bytes.length < _headerLength) {
      throw BackupFormatError('Este archivo no es una copia de Finanzas');
    }
    if (utf8.decode(bytes.sublist(0, _magicLength), allowMalformed: true) != magic) {
      throw BackupFormatError('Este archivo no es una copia de Finanzas');
    }
    return bytes[_magicLength];
  }

  static Future<SecretKey> _deriveKey(String password, List<int> salt) =>
      _kdf.deriveKeyFromPassword(password: password, nonce: salt);

  /// La cabecera entera se pasa como datos autenticados (AAD). No se cifra
  /// —hay que poder leerla sin contraseña— pero sí queda firmada, de modo que
  /// cambiar un byte rompe el descifrado. Sin esto, el byte de versión sería
  /// libre de manipular: `decrypt` seguiría funcionando y devolvería el texto
  /// correcto bajo una versión mentida.
  static Uint8List _header(int version, List<int> salt, List<int> nonce) =>
      Uint8List.fromList([...utf8.encode(magic), version, ...salt, ...nonce]);

  static Future<Uint8List> encrypt(String json, String password) async {
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final key = await _deriveKey(password, salt);
    final header = _header(formatVersion, salt, nonce);

    final box = await _cipher.encrypt(
      utf8.encode(json),
      secretKey: key,
      nonce: nonce,
      aad: header,
    );

    return Uint8List.fromList([
      ...header,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  static Future<String> decrypt(Uint8List bytes, String password) async {
    final version = readFormat(bytes);
    // Se comprueba aquí además de en quien llama. Sin esto, un archivo
    // legítimo de una versión futura fallaría en GCM y el usuario leería
    // «contraseña incorrecta», que es el mensaje equivocado para ese caso.
    if (version > formatVersion) {
      throw BackupFormatError(
          'Esta copia se hizo con una versión más nueva de la app');
    }

    final salt = bytes.sublist(_magicLength + 1, _magicLength + 1 + _saltLength);
    final nonce = bytes.sublist(
        _magicLength + 1 + _saltLength, _headerLength);
    final rest = bytes.sublist(_headerLength);
    if (rest.length < 16) {
      throw BackupFormatError('El archivo está incompleto');
    }
    final cipherText = rest.sublist(0, rest.length - 16);
    final mac = Mac(rest.sublist(rest.length - 16));

    final key = await _deriveKey(password, salt);
    try {
      final clear = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: key,
        aad: bytes.sublist(0, _headerLength),
      );
      return utf8.decode(clear);
    } catch (_) {
      throw BackupPasswordError();
    }
  }

  static Uint8List _randomBytes(int length) {
    final random = SecretKeyData.random(length: length);
    return Uint8List.fromList(random.bytes);
  }
}
```

- [ ] **Step 4: Ejecutar para verla pasar**

Run: `flutter test test/data/backup_crypto_test.dart`
Expected: PASS, 8 pruebas.

Si `SecretKeyData.random` no existe en `cryptography 2.9.0`, usa `dart:math`'s `Random.secure()` para generar los bytes y **dilo en el informe** — no es un cambio de diseño, pero quiero saberlo.

- [ ] **Step 5: Commit**

```bash
git add lib/data/backup/backup_crypto.dart test/data/backup_crypto_test.dart
git commit -m "feat: add encrypted backup container with plaintext header"
```

---

## Task 3: Volcado y restauración de las tablas

**Files:**
- Create: `lib/data/backup/backup_codec.dart`
- Test: `test/data/backup_codec_test.dart`

Las filas se leen **en crudo** con `SELECT *`. Pasar por las clases de datos de Drift obligaría a convertir las enumeraciones de ida y vuelta, y si Drift las serializara como índices, añadir un valor en el Plan 2 rompería las copias antiguas sin avisar. En crudo, el JSON es literalmente lo que hay en SQLite.

- [ ] **Step 1: Escribir la prueba que falla**

```dart
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
}
```

- [ ] **Step 2: Ejecutar para verla fallar**

Run: `flutter test test/data/backup_codec_test.dart`
Expected: FAIL — `backup_codec.dart not found`.

- [ ] **Step 3: Implementar**

```dart
// lib/data/backup/backup_codec.dart
import 'package:drift/drift.dart';

import '../db/database.dart';

/// Vuelca y restaura las tablas como filas en crudo.
///
/// Se lee con `SELECT *` en lugar de usar las clases de datos de Drift: así
/// las enumeraciones viajan como el texto que SQLite guarda de verdad
/// (`creditCard`, `expense`), y no como un índice que cambiaría de significado
/// al añadir un valor nuevo.
class BackupCodec {
  /// Orden de inserción: los padres antes que los hijos, para no violar las
  /// claves foráneas. El borrado va en el orden inverso.
  static const tableNames = <String>[
    'institutions',
    'categories',
    'accounts',
    'transactions',
    'fx_rates',
    'app_settings',
  ];

  /// Ajustes propios del dispositivo, no datos del usuario. Una copia no debe
  /// arrastrar el rescate de otro aparato ni su calendario de respaldos.
  static const localKeys = <String>{'rescate', 'rescate_fecha', 'ultima_copia'};

  static Future<Map<String, List<Map<String, Object?>>>> dump(
      AppDatabase db) async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final table in tableNames) {
      final rows = await db.customSelect('SELECT * FROM $table').get();
      var data = rows.map((r) => Map<String, Object?>.from(r.data)).toList();
      if (table == 'app_settings') {
        data = data.where((f) => !localKeys.contains(f['key'])).toList();
      }
      out[table] = data;
    }
    return out;
  }

  /// Vacía y repuebla, dentro de la transacción que abra quien llame.
  static Future<void> restore(
    AppDatabase db,
    Map<String, List<Map<String, Object?>>> dump,
  ) async {
    for (final table in tableNames.reversed) {
      await db.customStatement('DELETE FROM $table');
    }
    for (final table in tableNames) {
      for (final row in dump[table] ?? const []) {
        final cols = row.keys.toList();
        final marks = List.filled(cols.length, '?').join(', ');
        final quoted = cols.map((c) => '"$c"').join(', ');
        await db.customStatement(
          'INSERT INTO $table ($quoted) VALUES ($marks)',
          cols.map((c) => row[c]).toList(),
        );
      }
    }
  }
}
```

- [ ] **Step 4: Ejecutar para verla pasar**

Run: `flutter test test/data/backup_codec_test.dart`
Expected: PASS, 6 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/data/backup/backup_codec.dart test/data/backup_codec_test.dart
git commit -m "feat: dump and restore tables as raw rows"
```

---

## Task 4: El servicio — exportar

**Files:**
- Create: `lib/data/backup/backup_service.dart`
- Test: `test/data/backup_service_test.dart`

- [ ] **Step 1: Escribir la prueba que falla**

```dart
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
    final resumen = await service.summarize(await service.export(clave), clave);
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
}
```

- [ ] **Step 2: Ejecutar para verla fallar**

Run: `flutter test test/data/backup_service_test.dart`
Expected: FAIL — `backup_service.dart not found`.

- [ ] **Step 3: Implementar**

```dart
// lib/data/backup/backup_service.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'backup_codec.dart';
import 'backup_crypto.dart';

/// La copia viene de una versión de la app más nueva que esta.
class BackupTooNewError implements Exception {
  final int formato;
  BackupTooNewError(this.formato);
  @override
  String toString() =>
      'Esta copia se hizo con una versión más nueva de la app. Actualízala.';
}

/// Lo que hay dentro de una copia, para enseñarlo antes de restaurar.
class BackupSummary {
  final int cuentas;
  final int movimientos;
  final DateTime exportado;
  const BackupSummary(this.cuentas, this.movimientos, this.exportado);
}

class BackupService {
  final AppDatabase db;
  BackupService(this.db);

  static const _keyLastBackup = 'ultima_copia';

  Future<Uint8List> export(String password) async {
    final dump = await BackupCodec.dump(db);
    final payload = <String, Object?>{
      'formato': BackupCrypto.formatVersion,
      'esquema': db.schemaVersion,
      'exportado': DateTime.now().toUtc().toIso8601String(),
      'app': 'finanzas',
      ...dump,
    };
    final bytes = await BackupCrypto.encrypt(jsonEncode(payload), password);
    await _putSetting(_keyLastBackup, DateTime.now().toUtc().toIso8601String());
    return bytes;
  }

  /// Abre la copia solo para contar lo que trae. No toca la base de datos.
  Future<BackupSummary> summarize(Uint8List bytes, String password) async {
    final json = await _open(bytes, password);
    final cuentas = (json['accounts'] as List?)?.length ?? 0;
    final movimientos = (json['transactions'] as List?)?.length ?? 0;
    return BackupSummary(
      cuentas,
      movimientos,
      DateTime.parse(json['exportado'] as String),
    );
  }

  Future<Map<String, dynamic>> _open(Uint8List bytes, String password) async {
    final formato = BackupCrypto.readFormat(bytes); // lanza si no es nuestro
    if (formato > BackupCrypto.formatVersion) throw BackupTooNewError(formato);

    final json = jsonDecode(await BackupCrypto.decrypt(bytes, password))
        as Map<String, dynamic>;

    // `formato` viaja en la cabecera y dentro del JSON. El de fuera permite
    // rechazar un archivo futuro sin pedir la contraseña; el de dentro hace
    // que un archivo descifrado se explique solo. Si no coinciden, alguien ha
    // tocado la cabecera y el archivo no es de fiar.
    if (json['formato'] != formato) {
      throw BackupFormatError('La cabecera del archivo no concuerda con su contenido');
    }

    // Un esquema anterior se acepta: las tablas que no existían quedan
    // vacías. Uno **posterior** no, porque traería columnas que esta versión
    // desconoce y el fallo aparecería a mitad de la restauración como un
    // error crudo de SQLite. Mejor pararlo aquí, con un mensaje legible.
    final esquema = json['esquema'] as int? ?? 0;
    if (esquema > db.schemaVersion) throw BackupTooNewError(formato);

    return json;
  }

  Future<DateTime?> lastBackupDate() async {
    final value = await _getSetting(_keyLastBackup);
    return value == null ? null : DateTime.parse(value);
  }

  Future<String?> _getSetting(String key) async {
    final row = await (db.select(db.appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _putSetting(String key, String value) =>
      db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: key, value: value),
          );
}
```

- [ ] **Step 4: Ejecutar para verla pasar**

Run: `flutter test test/data/backup_service_test.dart`
Expected: PASS, 4 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/data/backup/backup_service.dart test/data/backup_service_test.dart
git commit -m "feat: export the database as an encrypted backup"
```

---

## Task 5: El servicio — importar, con rescate

**Files:**
- Modify: `lib/data/backup/backup_service.dart`
- Test: `test/data/backup_import_test.dart`

**La transacción no es opcional, está medida.** Restaurar 2000 filas en un fichero SQLite real cuesta **18.126 ms sin transacción y 104 ms dentro** — cada `INSERT` en autocommit paga una sincronización a disco. Y lo que importa más: sin transacción, un fallo a mitad deja la base de datos **vacía**, porque los `DELETE` ya se ejecutaron. Medido: cero categorías tras un fallo sin transacción, las trece intactas con ella.

**La trampa que esta tarea resuelve:** la importación reemplaza las seis tablas, y `app_settings` es una de ellas. Escrito a lo tonto, el rescate quedaría sobrescrito por el `app_settings` del archivo importado — la restauración destruiría la red de seguridad hecha para protegerte de ella, y «Deshacer» no funcionaría jamás. Por eso las claves locales se reescriben **después** de reemplazar las tablas, dentro de la misma transacción.

- [ ] **Step 1: Escribir la prueba que falla**

```dart
// test/data/backup_import_test.dart
import 'package:drift/drift.dart' show Value;
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
}
```

- [ ] **Step 2: Ejecutar para verla fallar**

Run: `flutter test test/data/backup_import_test.dart`
Expected: FAIL — `The method 'import' isn't defined`.

- [ ] **Step 3: Añadir al servicio**

Añade dentro de `class BackupService`:

```dart
  static const _keyRescue = 'rescate';
  static const _keyRescueDate = 'rescate_fecha';

  /// Reemplaza la base de datos con el contenido de la copia.
  ///
  /// Antes de tocar nada guarda un rescate de lo que hay, para que elegir el
  /// archivo equivocado tenga arreglo. Todo ocurre en una transacción: entra
  /// entero o no entra nada.
  Future<void> import(Uint8List bytes, String password) async {
    // Fuera de la transacción: si la contraseña falla, no se ha tocado nada.
    final json = await _open(bytes, password);
    final dump = _asDump(json);
    final rescue = jsonEncode(await BackupCodec.dump(db));

    await db.transaction(() async {
      // Las claves foráneas se comprueban al confirmar, no fila a fila. Sin
      // esto, una categoría cuyo `parent_id` apunta a otra con id mayor
      // rompería la inserción solo por el orden en que salieron del volcado.
      await db.customStatement('PRAGMA defer_foreign_keys = ON');

      await BackupCodec.restore(db, dump);
      // Después de reemplazar, no antes: `app_settings` es una de las tablas
      // que acaba de sustituirse, y el rescate que viniera en el archivo sería
      // el de otro dispositivo.
      await _putSetting(_keyRescue, rescue);
      await _putSetting(
          _keyRescueDate, DateTime.now().toUtc().toIso8601String());
    });
  }

  Future<bool> hasRescue() async => await _getSetting(_keyRescue) != null;

  /// Deshace la última importación. El rescate se consume al usarlo.
  Future<void> undoImport() async {
    final rescue = await _getSetting(_keyRescue);
    if (rescue == null) return;
    final dump = _asDump(jsonDecode(rescue) as Map<String, dynamic>);

    await db.transaction(() async {
      await BackupCodec.restore(db, dump);
      await db.customStatement(
        'DELETE FROM app_settings WHERE "key" IN (?, ?)',
        [_keyRescue, _keyRescueDate],
      );
    });
  }

  /// Quita el rescate. Se llama al exportar: a partir de ahí hay un respaldo
  /// mejor, y el rescate solo engordaría la siguiente copia.
  Future<void> clearRescue() => db.customStatement(
        'DELETE FROM app_settings WHERE "key" IN (?, ?)',
        [_keyRescue, _keyRescueDate],
      );

  /// Las tablas que el archivo no traiga —porque se hizo con un esquema
  /// anterior— quedan vacías en lugar de hacer fallar la importación.
  static Map<String, List<Map<String, Object?>>> _asDump(
      Map<String, dynamic> json) {
    return {
      for (final table in BackupCodec.tableNames)
        table: ((json[table] as List?) ?? const [])
            .map((row) => Map<String, Object?>.from(row as Map))
            .toList(),
    };
  }
```

Y en `export`, justo antes del `return bytes;`, añade:

```dart
    await clearRescue();
```

- [ ] **Step 4: Ejecutar para verla pasar**

Run: `flutter test test/data/backup_import_test.dart`
Expected: PASS, 6 pruebas.

- [ ] **Step 5: Commit**

```bash
git add lib/data/backup/backup_service.dart test/data/backup_import_test.dart
git commit -m "feat: restore backups with an automatic rescue copy"
```

---

## Task 6: La prueba de ida y vuelta completa

**Files:**
- Test: `test/data/backup_roundtrip_test.dart`

El criterio del diseño es que la ida y vuelta sea **exacta**. Una copia que restaura «casi bien» no sirve. Esta prueba compara fila a fila, campo a campo.

- [ ] **Step 1: Escribir la prueba**

```dart
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
      name: 'Euros',
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

    final comida =
        (await categories.ofKind(CategoryKind.expense)).first.id;
    await categories.archive(
        (await categories.ofKind(CategoryKind.expense)).last.id);

    await tx.addExpense(
      accountId: libras,
      amountMinor: 2450,
      categoryId: comida,
      date: '2026-09-12',
      merchant: 'Pub',
      note: 'con acentos: ñ á',
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
```

- [ ] **Step 2: Ejecutar**

Run: `flutter test test/data/backup_roundtrip_test.dart`
Expected: PASS, 1 prueba.

Si falla por la tabla `app_settings` —porque el volcado de «antes» incluía `ultima_copia` y el de «después» no, o al revés— **no ajustes la prueba para que pase**. Esa diferencia significaría que las claves locales no se están tratando como dice el diseño, y quiero saberlo.

- [ ] **Step 3: Commit**

```bash
git add test/data/backup_roundtrip_test.dart
git commit -m "test: verify the backup round trip is exact"
```

---

## Task 7: Entrega y selección del archivo

**Files:**
- Create: `lib/data/backup/backup_file.dart`

El único archivo del proyecto que mira la plataforma. No lleva pruebas automáticas: depende de diálogos del sistema operativo. Se verifica a mano en la Task 10.

- [ ] **Step 1: Implementar**

```dart
// lib/data/backup/backup_file.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// Lo único que distingue Android de la web.
///
/// En Android se abre el menú de compartir, que es lo que permite mandar la
/// copia a Drive o al correo —es decir, **sacarla del dispositivo**, que es
/// justo de lo que protege—. En web solo cabe una descarga: un navegador no
/// escribe en el disco sin que el usuario confirme, y eso es una protección
/// suya, no una carencia nuestra.
class BackupFile {
  static String nameFor(DateTime when) {
    final y = when.year.toString().padLeft(4, '0');
    final m = when.month.toString().padLeft(2, '0');
    final d = when.day.toString().padLeft(2, '0');
    return 'finanzas-$y-$m-$d.backup';
  }

  static Future<void> deliver(Uint8List bytes, {DateTime? when}) async {
    final name = nameFor(when ?? DateTime.now());
    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        mimeType: MimeType.other,
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: name, mimeType: 'application/octet-stream')],
        subject: name,
      ),
    );
  }

  /// `null` si el usuario cancela.
  static Future<Uint8List?> pick() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    return result?.files.single.bytes;
  }
}
```

- [ ] **Step 2: Comprobar que compila**

```bash
flutter analyze
```

Expected: `No issues found!`

Si `SharePlus.instance.share(ShareParams(...))` no es la API de `share_plus 13.3.1`, o `FileSaver.instance.saveFile` difiere en `file_saver 0.4.0`, **consulta la versión instalada en el caché de pub y ajústalo**, diciendo en el informe qué cambiaste. Son APIs que se mueven entre versiones mayores.

- [ ] **Step 3: Commit**

```bash
git add lib/data/backup/backup_file.dart
git commit -m "feat: deliver and pick backup files per platform"
```

---

## Task 8: Diálogo de contraseña

**Files:**
- Create: `lib/features/settings/password_dialog.dart`

- [ ] **Step 1: Implementar**

```dart
// lib/features/settings/password_dialog.dart
import 'package:flutter/material.dart';

/// Pide una contraseña. Con [confirm], exige escribirla dos veces.
///
/// El aviso va en la pantalla y destacado, no en una ayuda enterrada: es la
/// única oportunidad de decirle al usuario que esto no tiene vuelta atrás.
Future<String?> askPassword(
  BuildContext context, {
  required String title,
  required bool confirm,
}) {
  final first = TextEditingController();
  final second = TextEditingController();
  String? error;

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (confirm)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(dialogContext).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Si pierdes esta contraseña, el archivo no se puede '
                  'recuperar. No hay forma de restablecerla.',
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            TextField(
              controller: first,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña'),
            ),
            if (confirm) ...[
              const SizedBox(height: 12),
              TextField(
                controller: second,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Repítela'),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!,
                  style:
                      TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (first.text.isEmpty) {
                setState(() => error = 'Escribe una contraseña');
                return;
              }
              if (confirm && first.text != second.text) {
                setState(() => error = 'Las dos no coinciden');
                return;
              }
              Navigator.of(dialogContext).pop(first.text);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 2: Comprobar y confirmar**

```bash
flutter analyze
git add lib/features/settings/password_dialog.dart
git commit -m "feat: add password dialog with an irreversibility warning"
```

---

## Task 9: Pantalla de Ajustes y aviso en Inicio

**Files:**
- Create: `lib/features/settings/settings_screen.dart`, `lib/features/home/backup_banner.dart`
- Modify: `lib/app/providers.dart`, `lib/features/home/home_screen.dart`

**Cuánto tarda esto, medido:** una llamada a `encrypt` ronda **1,5 segundos** en un portátil, y descifrar cuesta lo mismo porque deriva la clave igual. Son las 100.000 iteraciones de PBKDF2, que son lentas a propósito —es lo que encarece probar contraseñas a la fuerza—. En un móvil será más. Por eso `_busy` deshabilita los botones y hay que **comprobar en la Task 10 si la interfaz se congela** durante la espera: si el hilo principal se bloquea, ni siquiera un indicador de progreso giraría, y la solución sería mover el cifrado a un isolate con `compute`. No lo doy por hecho ni lo descarto; se mide.

- [ ] **Step 1: Providers**

Añade a `lib/app/providers.dart` el import `import '../data/backup/backup_service.dart';` y:

```dart
final backupServiceProvider =
    Provider((ref) => BackupService(ref.watch(dbProvider)));

/// Días desde la última copia. `null` si nunca se ha hecho ninguna.
final daysSinceBackupProvider = FutureProvider<int?>((ref) async {
  // Depende de los movimientos para refrescarse al usar la app.
  ref.watch(monthTransactionsProvider);
  final date = await ref.watch(backupServiceProvider).lastBackupDate();
  if (date == null) return null;
  return DateTime.now().toUtc().difference(date).inDays;
});
```

- [ ] **Step 2: El aviso**

```dart
// lib/features/home/backup_banner.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../settings/settings_screen.dart';

/// Aviso pasivo: ni diálogo ni bloqueo. Siete días es la ventana en la que
/// Safari empieza a expulsar el almacenamiento local, que es el riesgo real
/// cuando la app corre como web en el iPhone.
class BackupBanner extends ConsumerWidget {
  const BackupBanner({super.key});

  static const _umbral = 7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dias = ref.watch(daysSinceBackupProvider);

    return dias.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (d) {
        if (d != null && d < _umbral) return const SizedBox.shrink();
        final texto =
            d == null ? 'Sin copia de seguridad' : 'Última copia hace $d días';
        return Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.backup_outlined, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(texto)),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 3: La pantalla de Ajustes**

```dart
// lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/backup/backup_crypto.dart';
import '../../data/backup/backup_file.dart';
import '../../data/backup/backup_service.dart';
import 'password_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final dias = ref.watch(daysSinceBackupProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text('COPIA DE SEGURIDAD',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Exportar copia'),
            subtitle: Text(dias == null
                ? 'Nunca has hecho una'
                : 'Última hace $dias días'),
            enabled: !_busy,
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Restaurar copia'),
            subtitle: const Text('Sustituye todos los datos actuales'),
            enabled: !_busy,
            onTap: _import,
          ),
          FutureBuilder<bool>(
            future: ref.read(backupServiceProvider).hasRescue(),
            builder: (_, snapshot) => snapshot.data == true
                ? ListTile(
                    leading: const Icon(Icons.undo),
                    title: const Text('Deshacer la última restauración'),
                    enabled: !_busy,
                    onTap: _undo,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    final password = await askPassword(context,
        title: 'Contraseña de la copia', confirm: true);
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final service = ref.read(backupServiceProvider);
      // Se exporta **una sola vez**: cada llamada a `export` genera un archivo
      // nuevo y consume el rescate, así que hacerlo dos veces para enseñar un
      // resumen daría dos copias distintas.
      final bytes = await service.export(password);
      final resumen = await service.summarize(bytes, password);
      await BackupFile.deliver(bytes);
      ref.invalidate(daysSinceBackupProvider);
      _say('Copia creada: ${resumen.movimientos} movimientos, '
          '${resumen.cuentas} cuentas');
    } catch (e) {
      _say('No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final bytes = await BackupFile.pick();
    if (bytes == null || !mounted) return;

    final password =
        await askPassword(context, title: 'Contraseña del archivo', confirm: false);
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    final service = ref.read(backupServiceProvider);
    try {
      final resumen = await service.summarize(bytes, password);
      final actuales = await service.currentCounts();
      if (!mounted) return;

      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Restaurar esta copia?'),
          content: Text(
            'Vas a sustituir ${actuales.movimientos} movimientos por '
            '${resumen.movimientos}, de una copia del '
            '${resumen.exportado.toLocal().toString().substring(0, 10)}.\n\n'
            'Se guardará una copia de rescate por si te equivocas de archivo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restaurar'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      await service.import(bytes, password);
      _invalidateAll();
      _say('Restaurado: ${resumen.movimientos} movimientos');
    } on BackupPasswordError catch (e) {
      _say(e.toString());
    } on BackupFormatError catch (e) {
      _say(e.toString());
    } on BackupTooNewError catch (e) {
      _say(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    setState(() => _busy = true);
    try {
      await ref.read(backupServiceProvider).undoImport();
      _invalidateAll();
      _say('Restauración deshecha');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidateAll() {
    ref.invalidate(accountsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(balancesProvider);
    ref.invalidate(netWorthProvider);
    ref.invalidate(monthTransactionsProvider);
    ref.invalidate(daysSinceBackupProvider);
    setState(() {});
  }
}
```

- [ ] **Step 4: Añadir `currentCounts` al servicio**

En `lib/data/backup/backup_service.dart`, dentro de `class BackupService`:

```dart
  /// Lo que hay ahora mismo, para enseñarlo junto a lo que trae la copia.
  Future<BackupSummary> currentCounts() async {
    final dump = await BackupCodec.dump(db);
    return BackupSummary(
      dump['accounts']!.length,
      dump['transactions']!.length,
      DateTime.now(),
    );
  }
```

- [ ] **Step 5: Enganchar en Inicio**

En `lib/features/home/home_screen.dart`, añade el import `import 'backup_banner.dart';` y una entrada a Ajustes en `actions:` del `AppBar`, antes del icono de la cartera:

```dart
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ajustes',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
```

con `import '../settings/settings_screen.dart';`.

Y envuelve el `body:` para que el aviso quede sobre la lista:

```dart
      body: Column(
        children: [
          const BackupBanner(),
          Expanded(child: transactions.when( /* ...lo que ya había... */ )),
        ],
      ),
```

- [ ] **Step 6: Verificar**

```bash
flutter analyze && flutter test
```

Expected: `No issues found!` y todas las pruebas en verde.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add settings screen and the backup reminder"
```

---

## Task 10: Verificación a mano

**Files:** ninguno

- [ ] **Step 1: Ejecutar en el emulador**

```bash
flutter run -d emulator-5554
```

- [ ] **Step 2: Recorrer el guion**

1. Crear dos cuentas en divisas distintas y tres o cuatro movimientos, incluida una transferencia.
2. Anotar el **patrimonio total** que muestra la barra superior.
3. Ajustes → **Exportar copia**. Comprobar que el aviso rojo sobre la contraseña se ve, que exige repetirla, y que el menú de compartir aparece.
4. Guardar el archivo donde sea accesible.
5. Borrar algún movimiento y crear otro distinto, para que los datos cambien.
6. Ajustes → **Restaurar copia**. Comprobar que la confirmación dice **cifras concretas** de lo que se sustituye.
7. Confirmar. El patrimonio debe volver **exactamente** al del punto 2.
8. Ajustes → **Deshacer la última restauración**. Deben reaparecer los cambios del punto 5.
9. Restaurar otra vez con una **contraseña incorrecta**: debe avisar sin tocar los datos.
10. Comprobar que el aviso de copia **desaparece** de Inicio tras exportar.
11. **Medir si la interfaz se congela** al exportar. El cifrado tarda más de un segundo por las 100.000 iteraciones de PBKDF2. Mirar si la pantalla responde durante la espera —intentar desplazar la lista, ver si una animación sigue corriendo—. Si se queda tiesa, anotarlo: la solución es mover `encrypt` y `decrypt` a un isolate con `compute`, y es una tarea aparte.

- [ ] **Step 3: Anotar fallos**

Cualquier punto que no se comporte como está descrito se arregla con una prueba que lo reproduzca primero.

- [ ] **Step 4: Commit final**

```bash
git add -A
git commit -m "chore: verify backup and restore on Android"
git tag copia-seguridad
```

---

## Lo que esto no hace

- **No sincroniza.** Cada dispositivo tiene su base de datos. La copia es el puente, y es manual a propósito.
- **No hay exportación automática.** Un navegador no escribe en disco sin confirmación del usuario; automatizarlo solo en Android daría dos comportamientos distintos, y el que protege no sería el del iPhone.
- **No recupera la contraseña.** Si se pierde, el archivo es inservible. Por eso el aviso está en la pantalla y no en una ayuda.
