import 'package:flutter_test/flutter_test.dart';
import 'package:nearlink/app.dart';
import 'package:nearlink/main.dart' as entry;
import 'package:nearlink/state/app_state.dart';

void main() {
  test('the whole app graph compiles', () {
    expect(NearlinkApp, isNotNull);
    expect(AppState, isNotNull);
    expect(entry.main, isNotNull);
  });
}
