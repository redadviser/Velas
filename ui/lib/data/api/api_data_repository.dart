import 'dart:typed_data';

import '../models/models.dart';
import '../repositories/data_repository.dart';
import 'api_client.dart';

/// Persistência na API. O isolamento entre utilizadores é garantido no
/// servidor — ver backend/src/modules (people, categories, gifts, messages).
class ApiDataRepository extends CachedDataRepository {
  ApiDataRepository(this._api);

  final ApiClient _api;

  static List<Map<String, dynamic>> _list(Object? v) => [for (final e in (v as List? ?? const [])) (e as Map).cast()];

  /// O servidor devolve um URL assinado e temporário para a fotografia.
  static Person _person(Map<String, dynamic> j) => Person.fromJson(j).copyWith(photoUrl: () => j['photo_url'] as String?);

  @override
  Future<AppData> fetchAll() async {
    final j = ((await _api.get('/data')) as Map).cast<String, dynamic>();
    return AppData(
      categories: _list(j['categories']).map(PersonCategory.fromJson).toList(),
      people: _list(j['people']).map(_person).toList(),
      gifts: _list(j['gift_ideas']).map(GiftIdea.fromJson).toList(),
      messages: _list(j['messages']).map(BirthdayMessage.fromJson).toList(),
    );
  }

  /// Envia a fotografia e devolve a pessoa com o novo caminho e URL.
  Future<Person> _uploadPhoto(Person person, Uint8List photo) async {
    final res = ((await _api.putBytes('/people/${person.id}/photo', photo, 'image/jpeg')) as Map).cast<String, dynamic>();
    return person.copyWith(photoPath: () => res['photo_path'] as String?, photoUrl: () => res['photo_url'] as String?);
  }

  @override
  Future<Person> persistPerson(Person person, Uint8List? photo, bool removePhoto) async {
    var saved = _person(((await _api.put('/people/${person.id}', person.toJson())) as Map).cast());
    if (photo != null) {
      saved = await _uploadPhoto(saved, photo);
    } else if (removePhoto && saved.photoPath != null) {
      await _api.delete('/people/${person.id}/photo');
      saved = saved.copyWith(photoPath: () => null, photoUrl: () => null);
    }
    return saved;
  }

  @override
  Future<List<Person>> persistPeople(List<Person> people, Map<String, Uint8List> photos) async {
    final saved = <Person>[];
    for (var i = 0; i < people.length; i += 500) {
      final chunk = people.sublist(i, i + 500 > people.length ? people.length : i + 500);
      final res = ((await _api.post('/people/import', {'people': chunk.map((p) => p.toJson()).toList()})) as Map);
      saved.addAll(_list(res['people']).map(_person));
    }
    // As fotografias vão depois, poucas de cada vez; uma falha não anula a importação.
    final byId = {for (final p in saved) p.id: p};
    final pending = photos.entries.where((e) => byId.containsKey(e.key)).toList();
    for (var i = 0; i < pending.length; i += 4) {
      await Future.wait([
        for (final e in pending.skip(i).take(4))
          _uploadPhoto(byId[e.key]!, e.value).then((p) => byId[e.key] = p).catchError((_) => byId[e.key]!),
      ]);
    }
    return byId.values.toList();
  }

  @override
  Future<void> removePerson(Person person) => _api.delete('/people/${person.id}');

  @override
  Future<void> persistCategory(PersonCategory category) => _api.put('/categories/${category.id}', category.toJson());

  @override
  Future<void> removeCategory(String id) => _api.delete('/categories/$id');

  @override
  Future<void> persistGift(GiftIdea gift) => _api.put('/gift-ideas/${gift.id}', gift.toJson());

  @override
  Future<void> removeGift(String id) => _api.delete('/gift-ideas/$id');

  @override
  Future<void> persistMessage(BirthdayMessage message) => _api.put('/messages/${message.id}', message.toJson());

  @override
  Future<void> removeMessage(String id) => _api.delete('/messages/$id');
}
