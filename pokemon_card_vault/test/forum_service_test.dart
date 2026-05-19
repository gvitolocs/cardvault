import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/services/forum_service.dart';

void main() {
  test('Forum models parse Supabase API rows', () {
    final category = ForumCategory.fromJson({
      'id': 'cards',
      'title': 'Cards',
      'description': 'Collecting and grading.',
      'icon_name': 'cards',
      'sort_order': 20,
      'topic_count': 3,
      'post_count': 9,
    });
    expect(category.id, 'cards');
    expect(category.iconName, 'cards');
    expect(category.topicCount, 3);

    final topic = ForumTopic.fromJson({
      'id': 'topic-1',
      'category_id': 'cards',
      'title': 'Grading ideas',
      'body': 'How should we compare graded cards?',
      'author_uid': 'uid-1',
      'author_name': 'collector',
      'author_photo_url': 'https://example.com/avatar.webp',
      'reply_count': 2,
      'status': 'open',
      'created_at': '2026-05-18T18:00:00Z',
      'updated_at': '2026-05-18T18:10:00Z',
    });
    expect(topic.categoryId, 'cards');
    expect(topic.authorName, 'collector');
    expect(topic.replyCount, 2);

    final post = ForumPost.fromJson({
      'id': 'post-1',
      'topic_id': 'topic-1',
      'body': 'Start with condition and certification.',
      'author_uid': 'uid-2',
      'author_name': 'validator',
      'created_at': '2026-05-18T18:12:00Z',
      'media': [
        {
          'id': 'media-1',
          'public_url': 'https://media.example/forum.webp',
          'mime_type': 'image/webp',
          'byte_size': 1024,
          'post_id': 'post-1',
        }
      ],
    });
    expect(post.topicId, 'topic-1');
    expect(post.media.single.url, 'https://media.example/forum.webp');
  });
}
