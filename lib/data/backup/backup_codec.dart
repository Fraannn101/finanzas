// lib/data/backup/backup_codec.dart
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
