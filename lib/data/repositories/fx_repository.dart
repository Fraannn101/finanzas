import 'package:drift/drift.dart';
import '../../core/currency.dart';
import '../../core/fx.dart';
import '../db/database.dart';

/// No hay ningún tipo de cambio conocido para esta divisa.
class NoFxRateAvailable implements Exception {
  final Currency currency;
  NoFxRateAvailable(this.currency);

  @override
  String toString() =>
      'Sin tipo de cambio para ${currency.code}. Conéctate a internet una vez '
      'o introdúcelo a mano.';
}

/// Un tipo resuelto para una fecha concreta. [isEstimated] indica que se ha
/// usado el tipo de un día anterior.
class ResolvedRate {
  final FxRate rate;
  final bool isEstimated;
  const ResolvedRate(this.rate, this.isEstimated);
}

class FxRepository {
  final AppDatabase db;
  FxRepository(this.db);

  Future<void> save(String date, FxRate rate, {required String source}) =>
      db.into(db.fxRates).insertOnConflictUpdate(FxRatesCompanion.insert(
            date: date,
            currency: rate.currency.code,
            rateToEurScaled: rate.scaled,
            source: source,
          ));

  Future<void> saveAll(String date, List<FxRate> rates,
          {required String source}) =>
      db.batch((b) {
        for (final rate in rates) {
          b.insert(
            db.fxRates,
            FxRatesCompanion.insert(
              date: date,
              currency: rate.currency.code,
              rateToEurScaled: rate.scaled,
              source: source,
            ),
            onConflict: DoUpdate((_) => FxRatesCompanion(
                  rateToEurScaled: Value(rate.scaled),
                  source: Value(source),
                )),
          );
        }
      });

  /// El tipo del día, o el último anterior marcado como estimado.
  Future<ResolvedRate> rateFor(Currency currency, String date) async {
    if (currency == Currency.eur) {
      return ResolvedRate(FxRate.identity(Currency.eur), false);
    }

    final exact = await (db.select(db.fxRates)
          ..where((r) => r.currency.equals(currency.code) & r.date.equals(date)))
        .getSingleOrNull();
    if (exact != null) {
      return ResolvedRate(FxRate(currency, exact.rateToEurScaled), false);
    }

    final previous = await (db.select(db.fxRates)
          ..where((r) =>
              r.currency.equals(currency.code) & r.date.isSmallerThanValue(date))
          ..orderBy([(r) => OrderingTerm(expression: r.date, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    if (previous != null) {
      return ResolvedRate(FxRate(currency, previous.rateToEurScaled), true);
    }

    throw NoFxRateAvailable(currency);
  }

  Future<String?> latestStoredDate() async {
    final row = await (db.select(db.fxRates)
          ..orderBy([(r) => OrderingTerm(expression: r.date, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row?.date;
  }
}
