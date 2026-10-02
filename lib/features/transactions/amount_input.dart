// lib/features/transactions/amount_input.dart

/// El importe que se está tecleando, como en una calculadora: los dígitos
/// entran por la derecha y los decimales salen solos.
class AmountInput {
  static const int _maxDigits = 12;

  int _minorUnits = 0;

  int get minorUnits => _minorUnits;
  bool get isEmpty => _minorUnits == 0;

  void pressDigit(int digit) {
    assert(digit >= 0 && digit <= 9);
    final next = _minorUnits * 10 + digit;
    if (next.toString().length > _maxDigits) return;
    _minorUnits = next;
  }

  void backspace() => _minorUnits ~/= 10;

  void clear() => _minorUnits = 0;

  /// «24,50» — sin símbolo de divisa, que lo pone la pantalla.
  String display(int decimalDigits) {
    final text = _minorUnits.toString().padLeft(decimalDigits + 1, '0');
    final cut = text.length - decimalDigits;
    return '${text.substring(0, cut)},${text.substring(cut)}';
  }
}
