import 'package:flutter_test/flutter_test.dart';
import 'package:eblan_messenger/main.dart';

void main() {
  testWidgets('App loads splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const EblanMessengerApp());
    expect(find.text('Eblan-Messenger'), findsOneWidget);
  });
}
