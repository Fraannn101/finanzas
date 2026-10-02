// lib/features/transactions/add_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/civil_date.dart';
import '../../core/currency.dart';
import '../../core/formatting.dart';
import '../../core/money.dart';
import '../../data/db/database.dart';
import '../../data/db/tables.dart';
import '../../data/repositories/fx_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import 'amount_input.dart';

Future<void> showAddSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddSheet(),
    );

class AddSheet extends ConsumerStatefulWidget {
  const AddSheet({super.key});

  @override
  ConsumerState<AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<AddSheet> {
  final _amount = AmountInput();
  TxType _type = TxType.expense;
  int? _accountId;
  int? _counterAccountId;
  int? _categoryId;
  String _date = todayCivil();
  bool _saving = false;
  bool _loading = true;

  /// Congelados al abrir la hoja, no enganchados al stream: ver la nota de
  /// clase sobre por qué los chips no deben reordenarse bajo el dedo.
  List<Account> _chipAccounts = const [];
  List<Category> _chipCategories = const [];

  @override
  void initState() {
    super.initState();
    _loadChips();
  }

  static CategoryKind _kindFor(TxType type) =>
      type == TxType.income ? CategoryKind.income : CategoryKind.expense;

  Future<void> _loadChips() async {
    final accounts =
        await ref.read(accountRepoProvider).watchMostUsed(limit: 4).first;
    final categories = await ref
        .read(categoryRepoProvider)
        .watchMostUsed(_kindFor(_type))
        .first;
    if (!mounted) return;
    setState(() {
      _chipAccounts = accounts;
      _chipCategories = categories;
      _accountId = accounts.isEmpty ? null : accounts.first.id;
      _loading = false;
    });
  }

  Future<void> _reloadCategories() async {
    final categories = await ref
        .read(categoryRepoProvider)
        .watchMostUsed(_kindFor(_type))
        .first;
    if (!mounted) return;
    setState(() {
      _chipCategories = categories;
      _categoryId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _shell(
        const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_chipAccounts.isEmpty) return _shell(const _NoAccountsYet());

    final account = _chipAccounts.firstWhere(
      (a) => a.id == _accountId,
      orElse: () => _chipAccounts.first,
    );
    final currency = Currency.byCode(account.currency);

    return _shell(
      SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _grabber(),
            const SizedBox(height: 10),
            _typeSelector(),
            const SizedBox(height: 14),
            _amountDisplay(currency),
            const SizedBox(height: 14),
            _label(_type == TxType.transfer ? 'Desde' : 'Cuenta'),
            _accountChips(
              _chipAccounts,
              selected: _accountId,
              onPick: (id) => setState(() {
                _accountId = id;
                if (_counterAccountId == id) _counterAccountId = null;
              }),
              showAll: true,
            ),
            if (_type == TxType.transfer) ...[
              const SizedBox(height: 12),
              _label('Hasta'),
              _accountChips(
                _chipAccounts.where((a) => a.id != _accountId).toList(),
                selected: _counterAccountId,
                onPick: (id) => setState(() => _counterAccountId = id),
                showAll: true,
              ),
            ] else ...[
              const SizedBox(height: 12),
              _label('Categoría'),
              _categoryChips(),
            ],
            const SizedBox(height: 14),
            _keypad(currency),
          ],
        ),
      ),
    );
  }

  Widget _shell(Widget child) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          top: 10,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14,
        ),
        child: child,
      );

  Widget _grabber() => Container(
        width: 34,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(3),
        ),
      );

  Widget _typeSelector() => SegmentedButton<TxType>(
        segments: const [
          ButtonSegment(value: TxType.expense, label: Text('Gasto')),
          ButtonSegment(value: TxType.income, label: Text('Ingreso')),
          ButtonSegment(value: TxType.transfer, label: Text('Transfer.')),
        ],
        selected: {_type},
        showSelectedIcon: false,
        onSelectionChanged: (s) {
          final previous = _type;
          setState(() {
            _type = s.first;
            _counterAccountId = null;
          });
          if (_kindFor(previous) != _kindFor(_type)) _reloadCategories();
        },
      );

  Widget _amountDisplay(Currency currency) {
    final money = Money(_amount.minorUnits, currency);
    return Column(
      children: [
        Text(
          '${_amount.display(currency.decimalDigits)} ${currency.symbol}',
          style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        if (currency == Currency.eur)
          Text(currency.code, style: Theme.of(context).textTheme.bodySmall)
        else
          _EurEquivalent(money: money, date: _date),
      ],
    );
  }

  Widget _label(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(text.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall),
        ),
      );

  Widget _accountChips(
    List<Account> accounts, {
    required int? selected,
    required ValueChanged<int> onPick,
    bool showAll = true,
  }) {
    if (accounts.isEmpty && !showAll) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text('No hay otra cuenta a la que transferir',
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: accounts.length + (showAll ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          if (i == accounts.length) {
            return ActionChip(
              avatar: const Icon(Icons.more_horiz, size: 18),
              label: const Text('Todas'),
              onPressed: () => _pickFromAll(onPick),
            );
          }
          final a = accounts[i];
          final symbol = Currency.byCode(a.currency).symbol;
          return ChoiceChip(
            label: Text('${a.name} $symbol'),
            selected: a.id == selected,
            onSelected: (_) => onPick(a.id),
          );
        },
      ),
    );
  }

  /// Todas las cuentas activas, con su saldo, para llegar a las que no
  /// entraron entre los cuatro chips más usados.
  Future<void> _pickFromAll(ValueChanged<int> onPick) async {
    final all = await ref.read(accountRepoProvider).activeAccounts();
    // Se consulta el saldo en lugar de leer `balancesProvider`: en un arranque
    // en frío ese stream todavía no ha emitido, y el valor por defecto pintaría
    // 0,00 € en cuentas que tienen dinero. Un cero falso en una app de finanzas
    // es peor que no enseñar nada.
    final balances = await ref.read(accountRepoProvider).watchBalances().first;
    if (!mounted) return;

    final chosen = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final a in all)
              ListTile(
                title: Text(a.name),
                subtitle: Text(a.currency),
                trailing: Text(
                  formatMoney(balances[a.id] ??
                      Money.zero(Currency.byCode(a.currency))),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.of(sheetContext).pop(a.id),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    // Si la cuenta elegida no estaba entre los chips, se añade delante para
    // que se vea seleccionada en lugar de desaparecer del sitio donde se ha
    // tocado.
    if (!_chipAccounts.any((a) => a.id == chosen)) {
      final account = all.firstWhere((a) => a.id == chosen);
      setState(() => _chipAccounts = [account, ..._chipAccounts]);
    }
    onPick(chosen);
  }

  Widget _categoryChips() => SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _chipCategories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final c = _chipCategories[i];
            return ChoiceChip(
              label: Text('${c.icon} ${c.name}'),
              selected: c.id == _categoryId,
              onSelected: (_) => setState(() => _categoryId = c.id),
            );
          },
        ),
      );

  Widget _keypad(Currency currency) {
    Widget key(String label, VoidCallback onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: FilledButton.tonal(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(label, style: const TextStyle(fontSize: 17)),
            ),
          ),
        );

    Widget digits(List<int> row) => Row(
          children: [
            for (final d in row)
              key('$d', () => setState(() => _amount.pressDigit(d))),
          ],
        );

    return Column(
      children: [
        digits([1, 2, 3]),
        digits([4, 5, 6]),
        digits([7, 8, 9]),
        Row(
          children: [
            key('⌫', () => setState(_amount.backspace)),
            key('0', () => setState(() => _amount.pressDigit(0))),
            key('📅', _pickDate),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _canSave ? _save : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_date == todayCivil() ? 'Guardar' : 'Guardar · $_date'),
          ),
        ),
      ],
    );
  }

  bool get _canSave {
    if (_saving || _amount.isEmpty || _accountId == null) return false;
    if (_type == TxType.transfer) return _counterAccountId != null;
    return true;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseCivilDate(_date),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = civilDateOf(picked));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(transactionRepoProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      if (_type == TxType.expense) {
        await repo.addExpense(
          accountId: _accountId!,
          amountMinor: _amount.minorUnits,
          categoryId: _categoryId,
          date: _date,
        );
      } else if (_type == TxType.income) {
        await repo.addIncome(
          accountId: _accountId!,
          amountMinor: _amount.minorUnits,
          categoryId: _categoryId,
          date: _date,
        );
      } else {
        final done = await _saveTransfer(repo);
        if (!done) return; // el usuario canceló el segundo importe
      }
      navigator.pop();
    } on NoFxRateAvailable catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  /// Devuelve `false` si el usuario canceló el diálogo del segundo importe.
  Future<bool> _saveTransfer(TransactionRepository repo) async {
    final from = _chipAccounts.firstWhere((a) => a.id == _accountId);
    final to = _chipAccounts.firstWhere((a) => a.id == _counterAccountId);

    var counterAmount = _amount.minorUnits;
    if (from.currency != to.currency) {
      final entered = await _askCounterAmount(Currency.byCode(to.currency));
      if (entered == null) {
        if (mounted) setState(() => _saving = false);
        return false;
      }
      counterAmount = entered;
    }

    await repo.addTransfer(
      fromAccountId: _accountId!,
      toAccountId: _counterAccountId!,
      amountMinor: _amount.minorUnits,
      counterAmountMinor: counterAmount,
      date: _date,
    );
    return true;
  }

  /// En una transferencia entre divisas hacen falta los dos importes: de ahí
  /// sale el tipo real que aplicó el banco, comisión incluida.
  Future<int?> _askCounterAmount(Currency currency) {
    final input = AmountInput();
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text('¿Cuánto entró en ${currency.code}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${input.display(currency.decimalDigits)} ${currency.symbol}',
                style:
                    const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var d = 1; d <= 9; d++)
                    SizedBox(
                      width: 54,
                      child: FilledButton.tonal(
                        onPressed: () =>
                            setDialogState(() => input.pressDigit(d)),
                        child: Text('$d'),
                      ),
                    ),
                  SizedBox(
                    width: 54,
                    child: FilledButton.tonal(
                      onPressed: () => setDialogState(() => input.pressDigit(0)),
                      child: const Text('0'),
                    ),
                  ),
                  SizedBox(
                    width: 54,
                    child: FilledButton.tonal(
                      onPressed: () => setDialogState(input.backspace),
                      child: const Text('⌫'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: input.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(input.minorUnits),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// La equivalencia en euros bajo el importe.
///
/// El futuro se guarda en el estado en vez de crearse dentro de `build`: si
/// se creara ahí, cada pulsación del teclado lanzaría una consulta nueva y el
/// texto parpadearía entre «GBP» y «GBP · ≈ 28,70 €». El importe cambia a
/// cada tecla, pero el tipo de cambio solo depende de la divisa y la fecha.
class _EurEquivalent extends ConsumerStatefulWidget {
  final Money money;
  final String date;
  const _EurEquivalent({required this.money, required this.date});

  @override
  ConsumerState<_EurEquivalent> createState() => _EurEquivalentState();
}

class _EurEquivalentState extends ConsumerState<_EurEquivalent> {
  late Future<ResolvedRate> _rate;

  @override
  void initState() {
    super.initState();
    _rate = _load();
  }

  @override
  void didUpdateWidget(_EurEquivalent old) {
    super.didUpdateWidget(old);
    if (old.money.currency != widget.money.currency ||
        old.date != widget.date) {
      _rate = _load();
    }
  }

  Future<ResolvedRate> _load() =>
      ref.read(fxRepoProvider).rateFor(widget.money.currency, widget.date);

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return FutureBuilder<ResolvedRate>(
      future: _rate,
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return Text('${widget.money.currency.code} · sin tipo de cambio',
              style: style);
        }
        if (!snapshot.hasData) {
          return Text(widget.money.currency.code, style: style);
        }
        final resolved = snapshot.data!;
        final eur = resolved.rate.toEur(widget.money);
        final suffix = resolved.isEstimated ? ' · tipo estimado' : '';
        return Text(
          '${widget.money.currency.code} · ≈ ${formatMoney(eur)}$suffix',
          style: style,
        );
      },
    );
  }
}

class _NoAccountsYet extends StatelessWidget {
  const _NoAccountsYet();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Primero crea una cuenta',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text(
              'Abre la cartera arriba a la derecha y añade tu primera cuenta '
              'con su divisa.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}
