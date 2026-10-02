import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/core/currency.dart';
import 'package:finanzas/core/fx.dart';
import 'package:finanzas/data/db/database.dart';
import 'package:finanzas/data/repositories/fx_repository.dart';

void main() {
  late AppDatabase db;
  late FxRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FxRepository(db);
  });
  tearDown(() => db.close());

  test('el euro siempre vale uno, sin consultar nada', () async {
    final resolved = await repo.rateFor(Currency.eur, '2026-09-12');
    expect(resolved.rate.scaled, FxRate.scale);
    expect(resolved.isEstimated, isFalse);
  });

  test('devuelve el tipo del día si existe', () async {
    await repo.save('2026-09-12', const FxRate(Currency.gbp, 117234500), source: 'ecb');
    final resolved = await repo.rateFor(Currency.gbp, '2026-09-12');
    expect(resolved.rate.scaled, 117234500);
    expect(resolved.isEstimated, isFalse);
  });

  test('un sábado usa el tipo del viernes y NO lo marca estimado', () async {
    await repo.save('2026-09-11', const FxRate(Currency.gbp, 117234500), source: 'ecb');
    final resolved = await repo.rateFor(Currency.gbp, '2026-09-12'); // sábado
    expect(resolved.rate.scaled, 117234500);
    expect(resolved.isEstimated, isFalse);
  });

  test('un domingo tampoco se marca estimado', () async {
    await repo.save('2026-09-11', const FxRate(Currency.gbp, 117234500), source: 'ecb');
    final resolved = await repo.rateFor(Currency.gbp, '2026-09-13'); // domingo
    expect(resolved.isEstimated, isFalse);
  });

  test('un día laborable sin tipo propio sí se marca estimado', () async {
    await repo.save('2026-09-10', const FxRate(Currency.gbp, 117234500), source: 'ecb');
    final resolved = await repo.rateFor(Currency.gbp, '2026-09-11'); // viernes
    expect(resolved.isEstimated, isTrue);
  });

  test('sin ningún tipo conocido, avisa en vez de inventarse uno', () async {
    expect(
      () => repo.rateFor(Currency.usd, '2026-09-12'),
      throwsA(isA<NoFxRateAvailable>()),
    );
  });

  test('guardar dos veces el mismo día actualiza en vez de duplicar', () async {
    await repo.save('2026-09-12', const FxRate(Currency.gbp, 100000000), source: 'ecb');
    await repo.save('2026-09-12', const FxRate(Currency.gbp, 117234500), source: 'manual');
    final resolved = await repo.rateFor(Currency.gbp, '2026-09-12');
    expect(resolved.rate.scaled, 117234500);
  });

  test('no usa un tipo posterior a la fecha pedida', () async {
    await repo.save('2026-09-20', const FxRate(Currency.gbp, 117234500), source: 'ecb');
    expect(
      () => repo.rateFor(Currency.gbp, '2026-09-12'),
      throwsA(isA<NoFxRateAvailable>()),
    );
  });
}
