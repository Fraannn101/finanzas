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
      throw BackupFormatError(
          'La cabecera del archivo no concuerda con su contenido');
    }
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
