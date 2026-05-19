import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/forum_service.dart';

final forumServiceProvider = Provider<ForumService>((ref) => ForumService());

final forumCategoriesProvider = FutureProvider<List<ForumCategory>>((ref) {
  return ref.watch(forumServiceProvider).categories();
});

final forumTopicsProvider =
    FutureProvider.family<List<ForumTopic>, String?>((ref, categoryId) {
  return ref.watch(forumServiceProvider).topics(categoryId: categoryId);
});

final forumTopicProvider =
    FutureProvider.family<ForumTopic?, String>((ref, topicId) {
  return ref.watch(forumServiceProvider).topic(topicId);
});

final forumPostsProvider =
    FutureProvider.family<List<ForumPost>, String>((ref, topicId) {
  return ref.watch(forumServiceProvider).posts(topicId);
});
