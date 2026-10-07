import 'package:uuid/uuid.dart';

import '../models/models.dart';

/// Dados iniciais de uma conta nova no modo local. Na API o mesmo é feito
/// ao criar a conta (backend/src/modules/users/users.service.ts).
class DefaultData {
  const DefaultData._();

  static const _uuid = Uuid();

  static List<PersonCategory> categories() => [
    PersonCategory(id: _uuid.v4(), name: 'Família', color: 0, sort: 0),
    PersonCategory(id: _uuid.v4(), name: 'Amigos', color: 1, sort: 1),
    PersonCategory(id: _uuid.v4(), name: 'Trabalho', color: 4, sort: 2),
  ];

  static AppData initial() => AppData(categories: categories());
}
