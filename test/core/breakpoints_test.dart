import 'package:flutter_test/flutter_test.dart';
import 'package:createai_studio/core/design/breakpoints.dart';

void main() {
  group('Breakpoints.formFactorFor', () {
    test('below 600 is compact (phone)', () {
      expect(Breakpoints.formFactorFor(599), AppFormFactor.compact);
      expect(Breakpoints.formFactorFor(320), AppFormFactor.compact);
    });

    test('600 up to (not including) 840 is medium (tablet)', () {
      expect(Breakpoints.formFactorFor(600), AppFormFactor.medium);
      expect(Breakpoints.formFactorFor(839), AppFormFactor.medium);
    });

    test('840 and above is expanded (desktop)', () {
      expect(Breakpoints.formFactorFor(840), AppFormFactor.expanded);
      expect(Breakpoints.formFactorFor(1920), AppFormFactor.expanded);
    });
  });
}
