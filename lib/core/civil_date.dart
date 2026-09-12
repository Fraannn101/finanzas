/// Una fecha sin hora, como texto `YYYY-MM-DD`.
///
/// Se guarda en texto y no como marca de tiempo para que ningún cambio de
/// huso horario mueva un movimiento de día. Además ordena bien en SQL.
String civilDateOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseCivilDate(String iso) {
  final parts = iso.split('-');
  if (parts.length != 3) throw FormatException('Fecha inválida: $iso');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

String todayCivil() => civilDateOf(DateTime.now());

String firstDayOfMonth(DateTime d) => civilDateOf(DateTime(d.year, d.month, 1));

/// Día 0 del mes siguiente = último día de este mes. Resuelve febrero solo.
String lastDayOfMonth(DateTime d) => civilDateOf(DateTime(d.year, d.month + 1, 0));
