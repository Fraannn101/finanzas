// lib/data/repositories/account_repository.dart
import 'package:drift/drift.dart';
import '../../core/currency.dart';
import '../db/database.dart';
import '../db/tables.dart';

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

  Future<List<Account>> activeAccounts() => (db.select(db.accounts)
        ..where((a) => a.isArchived.equals(false))
        ..orderBy([(a) => OrderingTerm(expression: a.sortOrder)]))
      .get();

  Stream<List<Account>> watchActiveAccounts() => (db.select(db.accounts)
        ..where((a) => a.isArchived.equals(false))
        ..orderBy([(a) => OrderingTerm(expression: a.sortOrder)]))
      .watch();

  /// Cuentas activas ordenadas por uso reciente: primero las que más
  /// movimientos tienen, y las que no tienen ninguno detrás, por `id`.
  ///
  /// No se puede resolver con `sortOrder`, que es un valor fijo: la
  /// frecuencia depende del historial y cambia sola según usas la app. Es la
  /// consulta que alimenta los chips de la hoja de añadir.
  Stream<List<Account>> watchMostUsed({int limit = 4}) => db
      .customSelect(
        '''
        SELECT a.* FROM accounts a
        LEFT JOIN transactions t
          ON t.account_id = a.id OR t.counter_account_id = a.id
        WHERE a.is_archived = 0
        GROUP BY a.id
        ORDER BY COUNT(t.id) DESC, a.id ASC
        LIMIT ?1
        ''',
        variables: [Variable<int>(limit)],
        readsFrom: {db.accounts, db.transactions},
      )
      .watch()
      .map((rows) => rows.map((r) => db.accounts.map(r.data)).toList());

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
