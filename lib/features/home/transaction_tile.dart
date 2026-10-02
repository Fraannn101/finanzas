// lib/features/home/transaction_tile.dart
import 'package:flutter/material.dart';
import '../../core/currency.dart';
import '../../core/formatting.dart';
import '../../core/money.dart';
import '../../data/db/database.dart';
import '../../data/db/tables.dart';

class TransactionTile extends StatelessWidget {
  final Txn tx;
  final String accountName;
  final String? categoryName;
  final String categoryIcon;
  final VoidCallback onTap;

  const TransactionTile({
    super.key,
    required this.tx,
    required this.accountName,
    required this.categoryName,
    required this.categoryIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final money = Money(tx.amountMinor, Currency.byCode(tx.currency));
    final isExpense = tx.type == TxType.expense;
    final isTransfer = tx.type == TxType.transfer;

    final color = isTransfer
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : isExpense
            ? const Color(0xFFE8422F)
            : const Color(0xFF12A150);

    return ListTile(
      onTap: onTap,
      leading: Text(isTransfer ? '🔄' : categoryIcon,
          style: const TextStyle(fontSize: 22)),
      title: Text(tx.merchant ?? categoryName ?? 'Transferencia'),
      subtitle: Row(
        children: [
          Flexible(child: Text(accountName, overflow: TextOverflow.ellipsis)),
          if (tx.fxIsEstimated) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Tipo de cambio estimado',
              child: Icon(Icons.schedule,
                  size: 13, color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ],
      ),
      trailing: Text(
        isTransfer ? formatMoney(money) : formatSigned(money, negate: isExpense),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
