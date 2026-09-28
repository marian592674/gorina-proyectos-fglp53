import 'package:flutter_test/flutter_test.dart';
import 'package:gorina_pick/core/password_hasher.dart';

void main() {
  test('hash pbkdf2 genera hex de 64 caracteres', () {
    final h = PasswordHasher.hash('1234', 'AABBCCDD');
    expect(h.length, 64);
    expect(h, PasswordHasher.hash('1234', 'AABBCCDD'));
  });
}
