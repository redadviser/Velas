import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/data/models/group_models.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/features/groups/payment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a fotografia de perfil vem do servidor e mantém-se ao editar o perfil', () {
    final p = UserProfile.fromJson(
      {'display_name': 'Inês', 'photo_url': 'https://api.test/files/u/avatar-1.jpg'},
      id: 'u',
      email: 'ines@ex.pt',
    );
    expect(p.photoUrl, 'https://api.test/files/u/avatar-1.jpg');
    expect(p.copyWith(name: 'Inês Costa').photoUrl, p.photoUrl);
    expect(p.copyWith(photoUrl: () => null).photoUrl, isNull);
    // Não vai no PATCH /me (a fotografia tem rota própria).
    expect(p.toPrefsJson().containsKey('photo_url'), isFalse);

    final m = GroupMember.fromJson({
      'id': 'm',
      'group_id': 'g',
      'user_id': 'u',
      'display_name': 'Inês',
      'photo_url': 'https://api.test/files/u/avatar-1.jpg',
    });
    expect(m.photoUrl, isNotNull);
    expect(m.copyWith(name: 'I').photoUrl, m.photoUrl);
  });

  testWidgets('mostra os logótipos do MB WAY, Revolut e PayPal', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.light]),
        home: Scaffold(body: Row(children: [for (final m in PaymentMethod.values) PaymentLogo(m)])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(3));
    for (final label in ['MB WAY', 'Revolut', 'PayPal']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    expect(find.byType(Icon), findsNWidgets(2)); // transferência e dinheiro
    expect(tester.takeException(), isNull);
  });
}
