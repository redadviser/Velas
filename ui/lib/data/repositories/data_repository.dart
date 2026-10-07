import 'dart:async';
import 'dart:typed_data';

import '../models/models.dart';

/// Contrato de acesso aos dados de um utilizador autenticado.
abstract class DataRepository {
  AppData get current;
  Stream<AppData> get changes;

  Future<void> load();

  Future<void> savePerson(Person person, {Uint8List? photo, bool removePhoto = false});
  Future<void> deletePerson(String id);

  /// Acrescenta várias pessoas de uma vez (importação de contactos).
  /// [photos] por id da pessoa.
  Future<void> importPeople(List<Person> people, {Map<String, Uint8List> photos = const {}});

  Future<void> saveCategory(PersonCategory category);
  Future<void> deleteCategory(String id);

  Future<void> saveGift(GiftIdea gift);
  Future<void> deleteGift(String id);

  Future<void> saveMessage(BirthdayMessage message);
  Future<void> deleteMessage(String id);

  void dispose();
}

/// Mantém os dados em memória e aplica as alterações de forma otimista:
/// a interface atualiza de imediato e, se o servidor falhar, reverte.
abstract class CachedDataRepository implements DataRepository {
  final _controller = StreamController<AppData>.broadcast();
  AppData _data = AppData.empty;

  @override
  AppData get current => _data;

  @override
  Stream<AppData> get changes async* {
    yield _data;
    yield* _controller.stream;
  }

  void emit(AppData data) {
    _data = data;
    if (!_controller.isClosed) _controller.add(data);
  }

  // Operações concretas de persistência.
  Future<AppData> fetchAll();
  Future<Person> persistPerson(Person person, Uint8List? photo, bool removePhoto);
  Future<void> removePerson(Person person);
  Future<List<Person>> persistPeople(List<Person> people, Map<String, Uint8List> photos);
  Future<void> persistCategory(PersonCategory category);
  Future<void> removeCategory(String id);
  Future<void> persistGift(GiftIdea gift);
  Future<void> removeGift(String id);
  Future<void> persistMessage(BirthdayMessage message);
  Future<void> removeMessage(String id);

  @override
  Future<void> load() async {
    final fresh = await fetchAll();
    emit(fresh.copyWith(loaded: true));
  }

  Future<void> _optimistic(AppData next, Future<void> Function() remote) async {
    final previous = _data;
    emit(next);
    try {
      await remote();
    } catch (_) {
      emit(previous);
      rethrow;
    }
  }

  static List<T> _upsert<T>(List<T> list, T item, String Function(T) id) {
    final i = list.indexWhere((e) => id(e) == id(item));
    return i == -1 ? [...list, item] : ([...list]..[i] = item);
  }

  @override
  Future<void> savePerson(Person person, {Uint8List? photo, bool removePhoto = false}) async {
    final existing = _data.person(person.id);
    // Mantém a fotografia anterior visível enquanto a nova é enviada.
    final optimistic = removePhoto
        ? person.copyWith(photoPath: () => null, photoUrl: () => null)
        : person.copyWith(photoUrl: () => existing?.photoUrl ?? person.photoUrl);
    await _optimistic(_data.copyWith(people: _upsert(_data.people, optimistic, (p) => p.id)), () async {
      final saved = await persistPerson(person, photo, removePhoto);
      emit(_data.copyWith(people: _upsert(_data.people, saved, (p) => p.id)));
    });
  }

  @override
  Future<void> deletePerson(String id) async {
    final person = _data.person(id);
    if (person == null) return;
    await _optimistic(
      _data.copyWith(
        people: _data.people.where((p) => p.id != id).toList(),
        gifts: _data.gifts.where((g) => g.personId != id).toList(),
        messages: _data.messages.where((m) => m.personId != id).toList(),
      ),
      () => removePerson(person),
    );
  }

  @override
  Future<void> importPeople(List<Person> people, {Map<String, Uint8List> photos = const {}}) async {
    if (people.isEmpty) return;
    await _optimistic(_data.copyWith(people: [..._data.people, ...people]), () async {
      final saved = await persistPeople(people, photos);
      var list = _data.people;
      for (final p in saved) {
        list = _upsert(list, p, (e) => e.id);
      }
      emit(_data.copyWith(people: list));
    });
  }

  @override
  Future<void> saveCategory(PersonCategory category) => _optimistic(
    _data.copyWith(categories: _upsert(_data.categories, category, (c) => c.id)),
    () => persistCategory(category),
  );

  @override
  Future<void> deleteCategory(String id) => _optimistic(
    _data.copyWith(
      categories: _data.categories.where((c) => c.id != id).toList(),
      people: [for (final p in _data.people) p.categoryId == id ? p.copyWith(categoryId: () => null) : p],
    ),
    () => removeCategory(id),
  );

  @override
  Future<void> saveGift(GiftIdea gift) =>
      _optimistic(_data.copyWith(gifts: _upsert(_data.gifts, gift, (g) => g.id)), () => persistGift(gift));

  @override
  Future<void> deleteGift(String id) =>
      _optimistic(_data.copyWith(gifts: _data.gifts.where((g) => g.id != id).toList()), () => removeGift(id));

  @override
  Future<void> saveMessage(BirthdayMessage message) => _optimistic(
    _data.copyWith(messages: _upsert(_data.messages, message, (m) => m.id)),
    () => persistMessage(message),
  );

  @override
  Future<void> deleteMessage(String id) =>
      _optimistic(_data.copyWith(messages: _data.messages.where((m) => m.id != id).toList()), () => removeMessage(id));

  @override
  void dispose() => _controller.close();
}
