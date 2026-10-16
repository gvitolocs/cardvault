import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/forum_service.dart';

final forumServiceProvider = Provider<ForumService>((ref) => ForumService());

final forumCategoriesProvider =
    StreamProvider<List<ForumCategory>>((ref) async* {
  final service = ref.watch(forumServiceProvider);
  final cached = await service.cachedCategories();
  yield cached;
  final fresh = await service.categories();
  if (!_sameCategories(cached, fresh)) {
    yield fresh;
  }
});

final forumTopicsProvider =
    StreamProvider.family<List<ForumTopic>, String?>((ref, categoryId) async* {
  final service = ref.watch(forumServiceProvider);
  final cached = await service.cachedTopics(categoryId: categoryId);
  yield cached;
  final fresh = await service.topics(categoryId: categoryId);
  if (!_sameTopics(cached, fresh)) {
    yield fresh;
  }
});

final forumTopicProvider =
    StreamProvider.family<ForumTopic?, String>((ref, topicId) async* {
  final service = ref.watch(forumServiceProvider);
  final cached = await service.cachedTopic(topicId);
  if (cached != null) {
    yield cached;
  }
  final fresh = await service.topic(topicId);
  if (fresh?.updatedAt != cached?.updatedAt || fresh?.id != cached?.id) {
    yield fresh;
  }
});

final forumPostsProvider =
    StreamProvider.family<List<ForumPost>, String>((ref, topicId) async* {
  final service = ref.watch(forumServiceProvider);
  final cached = await service.cachedPosts(topicId);
  yield cached;
  final fresh = await service.posts(topicId);
  if (!_samePosts(cached, fresh)) {
    yield fresh;
  }
});

bool _sameCategories(List<ForumCategory> a, List<ForumCategory> b) {
  return _sameIdsAndCounts(
    a.map((item) => '${item.id}:${item.topicCount}:${item.postCount}').toList(),
    b.map((item) => '${item.id}:${item.topicCount}:${item.postCount}').toList(),
  );
}

bool _sameTopics(List<ForumTopic> a, List<ForumTopic> b) {
  return _sameIdsAndCounts(
    a
        .map((item) =>
            '${item.id}:${item.replyCount}:${item.updatedAt.toIso8601String()}')
        .toList(),
    b
        .map((item) =>
            '${item.id}:${item.replyCount}:${item.updatedAt.toIso8601String()}')
        .toList(),
  );
}

bool _samePosts(List<ForumPost> a, List<ForumPost> b) {
  return _sameIdsAndCounts(
    a.map((item) => '${item.id}:${item.createdAt.toIso8601String()}').toList(),
    b.map((item) => '${item.id}:${item.createdAt.toIso8601String()}').toList(),
  );
}

bool _sameIdsAndCounts(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
