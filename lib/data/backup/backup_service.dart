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
    await clearRescue();
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
      throw BackupFormatError(
          'La cabecera del archivo no concuerda con su contenido');
    }

    // Un esquema anterior se acepta: las tablas que no existían quedan
    // vacías. Uno **posterior** no, porque traería columnas que esta versión
    // desconoce y el fallo aparecería a mitad de la restauración como un
    // error crudo de SQLite. Mejor pararlo aquí, con un mensaje legible.
    final esquema = json['esquema'] as int? ?? 0;
    if (esquema > db.schemaVersion) throw BackupTooNewError(formato);
    return json;
  }

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
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
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

  /// Lo que hay ahora mismo, para enseñarlo junto a lo que trae la copia.
  Future<BackupSummary> currentCounts() async {
    final dump = await BackupCodec.dump(db);
    return BackupSummary(
      dump['accounts']!.length,
      dump['transactions']!.length,
      DateTime.now(),
    );
  }

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
