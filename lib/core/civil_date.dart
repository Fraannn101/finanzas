/// Una fecha sin hora, como texto `YYYY-MM-DD`.
///
/// Se guarda en texto y no como marca de tiempo para que ningún cambio de
/// huso horario mueva un movimiento de día. Además ordena bien en SQL.
String civilDateOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Valida **solo la forma** (tres partes), no los rangos: `'2026-99-99'`
/// devuelve 2034-06-07 sin quejarse, porque `DateTime` normaliza los meses y
/// días fuera de rango rodando hacia delante. Basta mientras la entrada la
/// genere la propia app, que es el caso en toda la Fase 1. La importación de
/// CSV tendrá que envolverla con una validación de rangos y una comprobación
/// de ida y vuelta, que además atrapa fechas imposibles como `2026-02-30`.
DateTime parseCivilDate(String iso) {
  final parts = iso.split('-');
  if (parts.length != 3) throw FormatException('Fecha inválida: $iso');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

String todayCivil() => civilDateOf(DateTime.now());

String firstDayOfMonth(DateTime d) => civilDateOf(DateTime(d.year, d.month, 1));

/// Día 0 del mes siguiente = último día de este mes. Resuelve febrero solo.
String lastDayOfMonth(DateTime d) => civilDateOf(DateTime(d.year, d.month + 1, 0));
