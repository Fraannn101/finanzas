// lib/data/repositories/account_repository.dart
import 'package:drift/drift.dart';
import '../../core/civil_date.dart';
import '../../core/currency.dart';
import '../../core/money.dart';
import '../db/database.dart';
import '../db/tables.dart';
import 'fx_repository.dart';

/// Una institución con sus cuentas. `institution` es nulo para las cuentas
/// sueltas, como el efectivo.
class AccountGroup {
  final Institution? institution;
  final List<Account> accounts;
  const AccountGroup(this.institution, this.accounts);
}

class AccountRepository {
  final AppDatabase db;
  AccountRepository(this.db);

  Future<int> createInstitution({required String name, String icon = '🏦'}) =>
      db.into(db.institutions).insert(
            InstitutionsCompanion.insert(name: name, icon: Value(icon)),
          );

  Future<int> create({
    required String name,
    required Currency currency,
    required AccountType type,
    int? institutionId,
    int initialBalanceMinor = 0,
    int? creditLimitMinor,
  }) =>
      db.into(db.accounts).insert(AccountsCompanion.insert(
            name: name,
            currency: currency.code,
            type: type,
            institutionId: Value(institutionId),
            initialBalanceMinor: Value(initialBalanceMinor),
            creditLimitMinor: Value(creditLimitMinor),
          ));

  Future<Account> byId(int id) =>
      (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingle();

  /// El `id` como segundo criterio no es decorativo: `sortOrder` vale 0 en
  /// todas las filas, y ordenar por una columna con todos los valores
  /// iguales deja el orden a criterio del planificador de SQLite, que puede
  /// cambiar al añadir un índice.
  Future<List<Account>> activeAccounts() => (db.select(db.accounts)
        ..where((a) => a.isArchived.equals(false))
        ..orderBy([
          (a) => OrderingTerm(expression: a.sortOrder),
          (a) => OrderingTerm(expression: a.id),
        ]))
      .get();

  Stream<List<Account>> watchActiveAccounts() => (db.select(db.accounts)
        ..where((a) => a.isArchived.equals(false))
        ..orderBy([
          (a) => OrderingTerm(expression: a.sortOrder),
          (a) => OrderingTerm(expression: a.id),
        ]))
      .watch();

  /// Cuentas activas ordenadas por uso, para los chips de la hoja de añadir.
  ///
  /// Cuenta primero los movimientos desde [since] (90 días por defecto) y usa
  /// el total histórico solo para deshacer empates. «Frecuencia» es un ritmo,
  /// no un acumulado: contando toda la vida, una cuenta de efectivo con 500
  /// movimientos de hace dos años seguiría por delante de la que usas cada
  /// día, y lo haría para siempre. El total histórico como segundo criterio
  /// evita que, al estrenar la app o tras un parón, el orden quede aleatorio.
  ///
  /// No se puede resolver con `sortOrder`, que es un valor fijo.
  Stream<List<Account>> watchMostUsed({int limit = 4, String? since}) {
    final cutoff = since ??
        civilDateOf(DateTime.now().subtract(const Duration(days: 90)));
    return db
        .customSelect(
          '''
          SELECT a.*,
                 COUNT(t.id) AS all_time,
                 COUNT(CASE WHEN t.date >= ?2 THEN 1 END) AS recent
          FROM accounts a
          LEFT JOIN transactions t
            ON t.account_id = a.id OR t.counter_account_id = a.id
          WHERE a.is_archived = 0
          GROUP BY a.id
          ORDER BY recent DESC, all_time DESC, a.id ASC
          LIMIT ?1
          ''',
          variables: [Variable<int>(limit), Variable<String>(cutoff)],
          readsFrom: {db.accounts, db.transactions},
        )
        .watch()
        .map((rows) => rows.map((r) => db.accounts.map(r.data)).toList());
  }

  Future<void> archive(int id) => (db.update(db.accounts)
        ..where((a) => a.id.equals(id)))
      .write(const AccountsCompanion(isArchived: Value(true)));

  Future<void> rename(int id, String name) => (db.update(db.accounts)
        ..where((a) => a.id.equals(id)))
      .write(AccountsCompanion(name: Value(name)));

  /// La divisa es inmutable en cuanto la cuenta tiene movimientos: cambiarla
  /// reescribiría el histórico.
  Future<void> changeCurrency(int id, Currency currency) async {
    final count = await (db.selectOnly(db.transactions)
          ..addColumns([db.transactions.id.count()])
          ..where(db.transactions.accountId.equals(id) |
              db.transactions.counterAccountId.equals(id)))
        .getSingle();
    final used = count.read(db.transactions.id.count()) ?? 0;
    if (used > 0) {
      throw StateError(
        'La cuenta ya tiene movimientos: archívala y crea otra con la divisa correcta',
      );
    }
    await (db.update(db.accounts)..where((a) => a.id.equals(id)))
        .write(AccountsCompanion(currency: Value(currency.code)));
  }

  /// Saldo inicial, menos gastos y transferencias salientes, más ingresos y
  /// transferencias entrantes. Todo en la divisa nativa de la cuenta.
  static const String _balanceSql = '''
    SELECT a.id AS account_id,
           a.currency AS currency,
           a.initial_balance_minor
           + COALESCE((
               SELECT SUM(CASE t.type
                            WHEN 'income'   THEN  t.amount_minor
                            WHEN 'expense'  THEN -t.amount_minor
                            WHEN 'transfer' THEN -t.amount_minor
                          END)
               FROM transactions t WHERE t.account_id = a.id), 0)
           + COALESCE((
               SELECT SUM(t.counter_amount_minor)
               FROM transactions t
               WHERE t.counter_account_id = a.id AND t.type = 'transfer'), 0)
           AS balance_minor
    FROM accounts a
  ''';

  /// A propósito **sin** filtrar por archivadas: se pide el saldo de una
  /// cuenta concreta que ya conoces, y una archivada sigue teniendo saldo.
  /// El filtro de [watchBalances] es otra cosa: ahí se listan las activas.
  Future<Money> balanceOf(int accountId) async {
    final rows = await db
        .customSelect(
          '$_balanceSql WHERE a.id = ?1',
          variables: [Variable<int>(accountId)],
          readsFrom: {db.accounts, db.transactions},
        )
        .get();
    final row = rows.single;
    return Money(
      row.read<int>('balance_minor'),
      Currency.byCode(row.read<String>('currency')),
    );
  }

  /// Saldo de todas las cuentas activas, por id. Se recalcula solo cuando
  /// cambian las cuentas o los movimientos.
  Stream<Map<int, Money>> watchBalances() => db
      .customSelect(
        '$_balanceSql WHERE a.is_archived = 0',
        readsFrom: {db.accounts, db.transactions},
      )
      .watch()
      .map((rows) => {
            for (final row in rows)
              row.read<int>('account_id'): Money(
                row.read<int>('balance_minor'),
                Currency.byCode(row.read<String>('currency')),
              )
          });

  /// Suma de todas las cuentas activas, convertidas a euros con los tipos de
  /// [date]. Las tarjetas en negativo restan.
  Future<Money> netWorthEur(FxRepository fx, String date) async {
    final rows = await db
        .customSelect(
          '$_balanceSql WHERE a.is_archived = 0',
          readsFrom: {db.accounts, db.transactions},
        )
        .get();

    var totalMinor = 0;
    for (final row in rows) {
      final currency = Currency.byCode(row.read<String>('currency'));
      final balance = Money(row.read<int>('balance_minor'), currency);
      final resolved = await fx.rateFor(currency, date);
      totalMinor += resolved.rate.toEur(balance).minorUnits;
    }
    return Money(totalMinor, Currency.eur);
  }

  Future<List<AccountGroup>> groupedByInstitution() async {
    final institutions = await (db.select(db.institutions)
          ..orderBy([(i) => OrderingTerm(expression: i.sortOrder)]))
        .get();
    final accounts = await activeAccounts();

    final groups = <AccountGroup>[];
    for (final inst in institutions) {
      final mine = accounts.where((a) => a.institutionId == inst.id).toList();
      if (mine.isNotEmpty) groups.add(AccountGroup(inst, mine));
    }
    final loose = accounts.where((a) => a.institutionId == null).toList();
    if (loose.isNotEmpty) groups.add(AccountGroup(null, loose));
    return groups;
  }
}
