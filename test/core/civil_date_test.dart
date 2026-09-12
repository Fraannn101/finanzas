import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/civil_date.dart';

void main() {
  test('convierte una fecha a texto ISO sin hora', () {
    expect(civilDateOf(DateTime(2026, 9, 12, 23, 50)), '2026-09-12');
  });

  test('rellena con ceros meses y días de una cifra', () {
    expect(civilDateOf(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('vuelve a DateTime a medianoche local', () {
    final d = parseCivilDate('2026-09-12');
    expect(d.year, 2026);
    expect(d.month, 9);
    expect(d.day, 12);
    expect(d.hour, 0);
  });

  test('el primer y el último día del mes', () {
    expect(firstDayOfMonth(DateTime(2026, 9, 12)), '2026-09-01');
    expect(lastDayOfMonth(DateTime(2026, 2, 5)), '2026-02-28');
  });
}
