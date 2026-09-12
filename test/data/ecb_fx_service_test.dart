import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/repositories/fx_repository.dart';
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

  test('lee los atributos en cualquier orden', () {
    const alReves = '''
<Cube time="2026-09-11">
  <Cube rate="0.85300" currency="GBP"/>
</Cube>''';
    final rates = parseEcbDaily(alReves).rates;
    expect(rates.single.currency, Currency.gbp);
  });

  test('refresh descarga, guarda y no toca la red en las pruebas', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = FxRepository(db);
    final client = MockClient((_) async => http.Response(_xml, 200));

    expect(await EcbFxService(repo, client: client).refresh(), isTrue);
    final resolved = await repo.rateFor(Currency.gbp, '2026-09-11');
    expect(resolved.isEstimated, isFalse);
    expect(resolved.rate.scaled, closeTo(117233294, 2));
  });

  test('refresh devuelve false si el servicio falla', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final client = MockClient((_) async => http.Response('caído', 503));
    expect(await EcbFxService(FxRepository(db), client: client).refresh(), isFalse);
  });
}
