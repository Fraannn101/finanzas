// lib/features/transactions/edit_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/civil_date.dart';
import '../../core/currency.dart';
import '../../core/formatting.dart';
import '../../core/money.dart';
import '../../data/db/database.dart';
import '../../data/db/tables.dart';

class EditTransactionScreen extends ConsumerStatefulWidget {
  final int txId;
  const EditTransactionScreen({super.key, required this.txId});

  @override
  ConsumerState<EditTransactionScreen> createState() =>
      _EditTransactionScreenState();
}

class _EditTransactionScreenState extends ConsumerState<EditTransactionScreen> {
  Txn? _tx;
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  final _note = TextEditingController();
  int? _categoryId;
  String _date = todayCivil();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tx = await ref.read(transactionRepoProvider).byId(widget.txId);
    if (!mounted) return;
    final currency = Currency.byCode(tx.currency);
    setState(() {
      _tx = tx;
      _amount.text = (tx.amountMinor / currency.minorUnitsPerUnit)
          .toStringAsFixed(currency.decimalDigits);
      _merchant.text = tx.merchant ?? '';
      _note.text = tx.note ?? '';
      _categoryId = tx.categoryId;
      _date = tx.date;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tx = _tx;
    if (tx == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final currency = Currency.byCode(tx.currency);
    final isTransfer = tx.type == TxType.transfer;
    final kind =
        tx.type == TxType.income ? CategoryKind.income : CategoryKind.expense;
    final categories = (ref.watch(categoriesProvider).value ?? const <Category>[])
        .where((c) => c.kind == kind)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimiento'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Importe',
              suffixText: currency.symbol,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fecha'),
            trailing: Text(_date),
            onTap: _pickDate,
          ),
          if (!isTransfer) ...[
            const SizedBox(height: 8),
            const Text('Categoría'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in categories)
                  ChoiceChip(
                    label: Text('${c.icon} ${c.name}'),
                    selected: c.id == _categoryId,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _merchant,
            decoration: const InputDecoration(labelText: 'Comercio'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Nota'),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'Guardado en euros: '
            '${formatMoney(Money(tx.amountEurMinor, Currency.eur))}'
            '${tx.fxIsEstimated ? ' (tipo estimado)' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (isTransfer) ...[
            const SizedBox(height: 8),
            Text(
              'Las transferencias no se editan aquí: bórrala y vuelve a crearla.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: isTransfer ? null : _save,
            child: const Text('Guardar cambios'),
          ),
        ],
      ),
    );
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
    final tx = _tx!;
    final currency = Currency.byCode(tx.currency);
    final messenger = ScaffoldMessenger.of(context);
    final parsed = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) {
      messenger.showSnackBar(const SnackBar(content: Text('Importe inválido')));
      return;
    }

    final navigator = Navigator.of(context);
    await ref.read(transactionRepoProvider).update(
          tx.id,
          amountMinor: (parsed * currency.minorUnitsPerUnit).round(),
          categoryId: _categoryId,
          date: _date,
          merchant: _merchant.text.trim().isEmpty ? null : _merchant.text.trim(),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        );
    navigator.pop();
  }

  /// Borra con opción de deshacer: se reinsertan los mismos datos si el
  /// usuario se arrepiente antes de que desaparezca el aviso.
  Future<void> _delete() async {
    final tx = _tx!;
    final repo = ref.read(transactionRepoProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    await repo.delete(tx.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Movimiento borrado'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => repo.restore(tx),
        ),
      ),
    );
  }
}
