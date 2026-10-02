import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/features/transactions/amount_input.dart';

void main() {
  test('empieza en cero', () {
    expect(AmountInput().minorUnits, 0);
  });

  test('cada dígito desplaza a la izquierda', () {
    final input = AmountInput();
    input.pressDigit(2);
    input.pressDigit(4);
    input.pressDigit(5);
    input.pressDigit(0);
    expect(input.minorUnits, 2450); // 24,50
  });

  test('borrar quita el último dígito', () {
    final input = AmountInput()
      ..pressDigit(2)
      ..pressDigit(4)
      ..backspace();
    expect(input.minorUnits, 2);
  });

  test('no crece más allá del límite razonable', () {
    final input = AmountInput();
    for (var i = 0; i < 15; i++) {
      input.pressDigit(9);
    }
    expect(input.minorUnits, 999999999999); // 12 dígitos como tope
  });

  test('se formatea con los decimales de la divisa', () {
    final input = AmountInput()..pressDigit(5);
    expect(input.display(2), '0,05');
    input.pressDigit(0);
    expect(input.display(2), '0,50');
  });

  test('borrar desde cero no rompe nada', () {
    final input = AmountInput()..backspace();
    expect(input.minorUnits, 0);
    expect(input.isEmpty, isTrue);
  });

  test('clear vuelve a cero', () {
    final input = AmountInput()
      ..pressDigit(9)
      ..pressDigit(9)
      ..clear();
    expect(input.minorUnits, 0);
  });
}
