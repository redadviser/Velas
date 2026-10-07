import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../repositories/data_repository.dart';
import 'default_data.dart';

/// Persistência no próprio dispositivo (modo local, sem servidor).
class LocalDataRepository extends CachedDataRepository {
  LocalDataRepository(this._prefs, this._userId);

  final SharedPreferences _prefs;
  final String _userId;
  String? _docsPath;

  String get _key => 'velas.local.data.$_userId';

  Future<String> _docs() async => _docsPath ??= (await getApplicationDocumentsDirectory()).path;

  /// No iOS o caminho absoluto do contentor muda entre atualizações, por isso
  /// guarda-se apenas o caminho relativo e resolve-se ao carregar.
  Future<Person> _resolvePhoto(Person p) async {
    if (p.photoPath == null) return p;
    final file = File('${await _docs()}/${p.photoPath}');
    return p.copyWith(photoUrl: () => file.existsSync() ? file.path : null);
  }

  @override
  Future<AppData> fetchAll() async {
    final raw = _prefs.getString(_key);
    if (raw == null) {
      final initial = DefaultData.initial();
      await _write(initial);
      return initial;
    }
    final j = jsonDecode(raw) as Map<String, dynamic>;
    List<Map<String, dynamic>> list(String k) => ((j[k] as List?) ?? const []).cast<Map<String, dynamic>>();
    final people = <Person>[];
    for (final p in list('people').map(Person.fromJson)) {
      people.add(await _resolvePhoto(p));
    }
    return AppData(
      people: people,
      categories: list('categories').map(PersonCategory.fromJson).toList()..sort((a, b) => a.sort.compareTo(b.sort)),
      gifts: list('gift_ideas').map(GiftIdea.fromJson).toList(),
      messages: list('messages').map(BirthdayMessage.fromJson).toList(),
    );
  }

  Future<void> _write(AppData data) => _prefs.setString(_key, jsonEncode(data.toExportJson()));

  Future<void> _deleteFile(String? relative) async {
    if (relative == null) return;
    final f = File('${await _docs()}/$relative');
    if (f.existsSync()) await f.delete();
  }

  @override
  Future<Person> persistPerson(Person person, Uint8List? photo, bool removePhoto) async {
    var saved = person;
    if (removePhoto || photo != null) {
      await _deleteFile(person.photoPath);
      saved = saved.copyWith(photoPath: () => null, photoUrl: () => null);
    }
    if (photo != null) {
      final relative = 'photos/${person.id}-${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${await _docs()}/$relative');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(photo);
      saved = saved.copyWith(photoPath: () => relative, photoUrl: () => file.path);
    } else if (!removePhoto) {
      saved = await _resolvePhoto(saved);
    }
    final i = current.people.indexWhere((p) => p.id == saved.id);
    final people = [...current.people];
    i == -1 ? people.add(saved) : people[i] = saved;
    await _write(current.copyWith(people: people));
    return saved;
  }

  @override
  Future<List<Person>> persistPeople(List<Person> people, Map<String, Uint8List> photos) async {
    final saved = <Person>[];
    for (final p in people) {
      final photo = photos[p.id];
      if (photo == null) {
        saved.add(p);
        continue;
      }
      final relative = 'photos/${p.id}-${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${await _docs()}/$relative');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(photo);
      saved.add(p.copyWith(photoPath: () => relative, photoUrl: () => file.path));
    }
    final ids = {for (final p in saved) p.id};
    await _write(current.copyWith(people: [...current.people.where((p) => !ids.contains(p.id)), ...saved]));
    return saved;
  }

  @override
  Future<void> removePerson(Person person) async {
    await _deleteFile(person.photoPath);
    await _write(current);
  }

  @override
  Future<void> persistCategory(PersonCategory category) => _write(current);
  @override
  Future<void> removeCategory(String id) => _write(current);
  @override
  Future<void> persistGift(GiftIdea gift) => _write(current);
  @override
  Future<void> removeGift(String id) => _write(current);
  @override
  Future<void> persistMessage(BirthdayMessage message) => _write(current);
  @override
  Future<void> removeMessage(String id) => _write(current);
}
