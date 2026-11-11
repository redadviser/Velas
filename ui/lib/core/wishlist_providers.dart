import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/api_client.dart';
import '../data/models/models.dart';
import 'providers.dart';

/// A minha lista de desejos (só com servidor: sem conta, ninguém a veria).
class MyWishlist extends AsyncNotifier<List<WishItem>> {
  @override
  Future<List<WishItem>> build() async {
    final api = ref.watch(apiClientProvider);
    if (api == null) return const [];
    final rows = await api.get('/me/wishlist') as List;
    return [for (final r in rows) WishItem.fromJson((r as Map).cast<String, dynamic>())];
  }

  ApiClient get _api => ref.read(apiClientProvider)!;

  Future<void> save(WishItem item) async {
    final saved = WishItem.fromJson(
      ((await _api.put('/me/wishlist/${item.id}', item.toJson())) as Map).cast<String, dynamic>(),
    );
    final list = [...?state.value];
    final i = list.indexWhere((w) => w.id == saved.id);
    i < 0 ? list.add(saved) : list[i] = saved;
    state = AsyncData(list);
  }

  Future<void> remove(String id) async {
    await _api.delete('/me/wishlist/$id');
    state = AsyncData([...?state.value?.where((w) => w.id != id)]);
  }
}

final myWishlistProvider = AsyncNotifierProvider<MyWishlist, List<WishItem>>(MyWishlist.new);

typedef FriendWishlist = ({List<String> interests, List<WishItem> items});

/// Os gostos e a lista de desejos de um amigo; null se já não forem amigos.
final friendWishlistProvider = FutureProvider.autoDispose.family<FriendWishlist?, String>((ref, userId) async {
  final api = ref.watch(apiClientProvider);
  if (api == null) return null;
  try {
    final j = (await api.get('/friends/$userId/wishlist') as Map).cast<String, dynamic>();
    return (
      interests: (j['interests'] as List).cast<String>(),
      items: [for (final r in j['items'] as List) WishItem.fromJson((r as Map).cast<String, dynamic>())],
    );
  } on ApiException catch (e) {
    if (e.status == 404) return null;
    rethrow;
  }
});
