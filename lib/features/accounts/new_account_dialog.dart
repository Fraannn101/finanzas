// lib/features/accounts/new_account_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/currency.dart';
import '../../data/db/tables.dart';

class NewAccountDialog extends ConsumerStatefulWidget {
  const NewAccountDialog({super.key});

  @override
  ConsumerState<NewAccountDialog> createState() => _NewAccountDialogState();
}

class _NewAccountDialogState extends ConsumerState<NewAccountDialog> {
  final _name = TextEditingController();
  final _institution = TextEditingController();
  Currency _currency = Currency.eur;
  AccountType _type = AccountType.checking;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva cuenta'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _institution,
              decoration: const InputDecoration(
                labelText: 'Banco',
                hintText: 'Revolut, BBVA, Barclays…',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre de la cuenta',
                hintText: 'Libras, Cuenta corriente, Visa…',
              ),
            ),
            const SizedBox(height: 16),
            const Text('Divisa'),
            const SizedBox(height: 6),
            SegmentedButton<Currency>(
              segments: [
                for (final c in Currency.all)
                  ButtonSegment(value: c, label: Text('${c.code} ${c.symbol}')),
              ],
              selected: {_currency},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _currency = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              'La divisa no se puede cambiar una vez la cuenta tenga movimientos.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            const Text('Tipo'),
            const SizedBox(height: 6),
            DropdownButton<AccountType>(
              value: _type,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                    value: AccountType.checking, child: Text('Cuenta corriente')),
                DropdownMenuItem(value: AccountType.savings, child: Text('Ahorro')),
                DropdownMenuItem(value: AccountType.cash, child: Text('Efectivo')),
                DropdownMenuItem(
                    value: AccountType.creditCard, child: Text('Tarjeta de crédito')),
              ],
              onChanged: (v) => setState(() => _type = v ?? AccountType.checking),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Crear')),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ponle un nombre a la cuenta')));
      return;
    }
    setState(() => _saving = true);

    final repo = ref.read(accountRepoProvider);
    final navigator = Navigator.of(context);
    final institutionName = _institution.text.trim();

    int? institutionId;
    if (institutionName.isNotEmpty) {
      // Se reutiliza el banco si ya existe, para que «Revolut» no aparezca
      // tres veces al dar de alta sus tres bolsillos.
      final existing = await repo.institutionByName(institutionName);
      institutionId = existing ?? await repo.createInstitution(name: institutionName);
    }
    await repo.create(
      name: name,
      currency: _currency,
      type: _type,
      institutionId: institutionId,
    );
    navigator.pop();
  }
}
