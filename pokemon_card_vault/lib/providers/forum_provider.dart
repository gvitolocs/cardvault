import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/forum_service.dart';

final forumServiceProvider = Provider<ForumService>((ref) => ForumService());

final forumCategoriesProvider = StreamProvider<List<ForumCategory>>((ref) {
  return ref.watch(forumServiceProvider).categories();
});

final forumTopicsProvider =
    StreamProvider.family<List<ForumTopic>, String?>((ref, categoryId) {
  return ref.watch(forumServiceProvider).topics(categoryId: categoryId);
});

final forumTopicProvider =
    StreamProvider.family<ForumTopic?, String>((ref, topicId) {
  return ref.watch(forumServiceProvider).topic(topicId);
});

final forumPostsProvider =
    StreamProvider.family<List<ForumPost>, String>((ref, topicId) {
  return ref.watch(forumServiceProvider).posts(topicId);
});
