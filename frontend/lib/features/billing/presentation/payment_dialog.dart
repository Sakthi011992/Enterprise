import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../orders/data/orders_repository.dart';

final _enabledPaymentMethodsProvider = FutureProvider<List<String>>((ref) async {
  final res = await ref.read(dioProvider).get('/payments/methods/default');
  return (res.data as List).map((m) => m['method'].toString()).toList();
});

const _methodLabels = {
  'CASH': ('Cash', Icons.money),
  'UPI': ('UPI / QR', Icons.qr_code),
  'CARD': ('Card', Icons.credit_card),
};

class PaymentDialog extends ConsumerStatefulWidget {
  const PaymentDialog({super.key, required this.order});
  final Map order;
  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> {
  String? _method;
  late final _amount = TextEditingController(text: widget.order['grandTotal'].toString());
  bool _saving = false;

  Future<void> _pay() async {
    if (_method == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(ordersRepositoryProvider).pay(
            orderId: widget.order['id'] as String,
            amount: double.parse(_amount.text),
            method: _method!,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabledMethods = ref.watch(_enabledPaymentMethodsProvider);
    final t = context.tokens;
    return AlertDialog(
      title: Text('Payment — ${widget.order['invoiceNumber']}'),
      content: enabledMethods.when(
        loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
        error: (_, __) => const Text('Could not load payment methods'),
        data: (methods) {
          _method ??= methods.isNotEmpty ? methods.first : null;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Grand Total: ₹${widget.order['grandTotal']}',
                  style: Theme.of(context).textTheme.titleLarge),
              SizedBox(height: t.spacing.md),
              // Payment method selector chips
              Wrap(
                spacing: t.spacing.sm,
                children: methods.map((m) {
                  final info = _methodLabels[m];
                  return ChoiceChip(
                    avatar: Icon(info?.$2 ?? Icons.payment, size: 16),
                    label: Text(info?.$1 ?? m),
                    selected: _method == m,
                    onSelected: (_) => setState(() => _method = m),
                  );
                }).toList(),
              ),
              SizedBox(height: t.spacing.step(3)),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount received', prefixText: '₹ '),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: (_saving || _method == null) ? null : _pay,
          child: const Text('Confirm Payment'),
        ),
      ],
    );
  }
}
