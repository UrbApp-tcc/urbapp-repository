import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meu_app/main.dart';

void main() {
  test('UrbappApp can be instantiated', () {
    const app = UrbappApp();

    expect(app, isA<Widget>());
  });
}
