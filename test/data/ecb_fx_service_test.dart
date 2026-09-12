import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/data/services/ecb_fx_service.dart';

const _xml = '''<?xml version="1.0" encoding="UTF-8"?>
<gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01"
                 xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
  <Cube>
    <Cube time="2026-09-11">
      <Cube currency="USD" rate="1.0842"/>
      <Cube currency="GBP" rate="0.85300"/>
      <Cube currency="JPY" rate="161.23"/>
    </Cube>
  </Cube>
</gesmes:Envelope>''';

void main() {
  test('extrae la fecha de publicación', () {
    expect(parseEcbDaily(_xml).date, '2026-09-11');
  });

  test('invierte las cotizaciones a euros por unidad', () {
    final rates = parseEcbDaily(_xml).rates;
    final gbp = rates.firstWhere((r) => r.currency == Currency.gbp);
    // 1 / 0,853 = 1,17233...
    expect(gbp.scaled, closeTo(117233294, 2));
  });

  test('ignora las divisas que la app no soporta', () {
    final rates = parseEcbDaily(_xml).rates;
    expect(rates.map((r) => r.currency.code), containsAll(['USD', 'GBP']));
    expect(rates.length, 2); // el yen se descarta
  });

  test('un XML sin cotizaciones es un error de formato', () {
    expect(() => parseEcbDaily('<vacio/>'), throwsFormatException);
  });
}
