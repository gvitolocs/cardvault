import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/project_links.dart';
import '../providers/auth_provider.dart';
import '../providers/forum_provider.dart';
import '../services/forum_service.dart';
import '../widgets/site_footer.dart';

class ForumScreen extends ConsumerWidget {
  const ForumScreen({super.key, this.categoryId, this.topicId});

  final String? categoryId;
  final String? topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final profile = ref.watch(userProfileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: const _ForumTopBar(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.35,
            colors: [Color(0x2638BDF8), Color(0x00050816)],
          ),
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ForumHero(
                    signedIn: user != null,
                    onNewTopic: user == null
                        ? () => context.go('/auth?from=/forum')
                        : () =>
                            _showTopicDialog(context, ref, user.uid, profile),
                  ),
                  const SizedBox(height: 22),
                  if (topicId == null)
                    _ForumHome(categoryId: categoryId)
                  else
                    _TopicDetail(
                      topicId: topicId!,
                      onReply: user == null
                          ? () => context.go('/auth?from=/forum/topic/$topicId')
                          : () => _showReplyDialog(
                                context,
                                ref,
                                topicId!,
                                user.uid,
                                profile,
                              ),
                    ),
                  const SiteFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showTopicDialog(
    BuildContext context,
    WidgetRef ref,
    String uid,
    dynamic profile,
  ) {
    final title = TextEditingController();
    final body = TextEditingController();
    String selectedCategory = categoryId ?? 'general';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final categories =
              ref.watch(forumCategoriesProvider).valueOrNull ?? [];
          if (categories.isNotEmpty &&
              !categories.any((category) => category.id == selectedCategory)) {
            selectedCategory = categories.first.id;
          }

          return _ForumDialog(
            title: 'Start a discussion',
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  dropdownColor: const Color(0xFF111936),
                  decoration: _forumInputDecoration(
                    'Category',
                    Icons.folder_open_outlined,
                  ),
                  items: [
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.title),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _ForumTextField(
                  controller: title,
                  label: 'Topic title',
                  icon: Icons.title,
                ),
                const SizedBox(height: 12),
                _ForumTextField(
                  controller: body,
                  label: 'What do you want to discuss?',
                  icon: Icons.notes_outlined,
                  maxLines: 5,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    final topicId =
                        await ref.read(forumServiceProvider).createTopic(
                              categoryId: selectedCategory,
                              title: title.text,
                              body: body.text,
                              authorUid: uid,
                              authorName: _authorName(profile),
                              authorPhotoUrl: profile?.photoUrl as String?,
                            );
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      context.go('/forum/topic/$topicId');
                    }
                  } catch (error) {
                    if (dialogContext.mounted) {
                      _showForumMessage(dialogContext, error.toString());
                    }
                  }
                },
                child: const Text('Publish'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      title.dispose();
      body.dispose();
    });
  }

  void _showReplyDialog(
    BuildContext context,
    WidgetRef ref,
    String topicId,
    String uid,
    dynamic profile,
  ) {
    final body = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => _ForumDialog(
        title: 'Reply',
        body: _ForumTextField(
          controller: body,
          label: 'Write your reply',
          icon: Icons.reply_outlined,
          maxLines: 5,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await ref.read(forumServiceProvider).createPost(
                      topicId: topicId,
                      body: body.text,
                      authorUid: uid,
                      authorName: _authorName(profile),
                      authorPhotoUrl: profile?.photoUrl as String?,
                    );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  _showForumMessage(dialogContext, error.toString());
                }
              }
            },
            child: const Text('Reply'),
          ),
        ],
      ),
    ).whenComplete(body.dispose);
  }

  String _authorName(dynamic profile) {
    final name = profile?.displayName as String?;
    return name == null || name.trim().isEmpty ? 'Pokoin user' : name.trim();
  }
}

class _ForumHome extends ConsumerWidget {
  const _ForumHome({required this.categoryId});

  final String? categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(forumCategoriesProvider);
    final topics = ref.watch(forumTopicsProvider(categoryId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        categories.when(
          data: (items) => _CategoryRail(items: items, selected: categoryId),
          loading: () => const _ForumPanel(child: _ForumLoading()),
          error: (error, _) =>
              _ForumPanel(child: _ForumError(message: error.toString())),
        ),
        const SizedBox(height: 18),
        topics.when(
          data: (items) => _TopicList(topics: items),
          loading: () => const _ForumPanel(child: _ForumLoading()),
          error: (error, _) =>
              _ForumPanel(child: _ForumError(message: error.toString())),
        ),
      ],
    );
  }
}

class _TopicDetail extends ConsumerWidget {
  const _TopicDetail({required this.topicId, required this.onReply});

  final String topicId;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topic = ref.watch(forumTopicProvider(topicId));
    final posts = ref.watch(forumPostsProvider(topicId));

    return topic.when(
      data: (topic) {
        if (topic == null) {
          return const _ForumPanel(
            child: _ForumError(message: 'Topic not found.'),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ForumPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        context.go('/forum/category/${topic.categoryId}'),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to category'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    topic.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AuthorLine(
                    name: topic.authorName,
                    photoUrl: topic.authorPhotoUrl,
                    date: topic.createdAt,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    topic.body,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      height: 1.55,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onReply,
                    icon: const Icon(Icons.reply_outlined),
                    label: const Text('Reply'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            posts.when(
              data: (items) => _Replies(posts: items),
              loading: () => const _ForumPanel(child: _ForumLoading()),
              error: (error, _) =>
                  _ForumPanel(child: _ForumError(message: error.toString())),
            ),
          ],
        );
      },
      loading: () => const _ForumPanel(child: _ForumLoading()),
      error: (error, _) =>
          _ForumPanel(child: _ForumError(message: error.toString())),
    );
  }
}

class _ForumHero extends StatelessWidget {
  const _ForumHero({required this.signedIn, required this.onNewTopic});

  final bool signedIn;
  final VoidCallback onNewTopic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111B3F), Color(0xFF0B1020)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 18,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pokoin Forum',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Discuss cards, PKN, wPKN liquidity, marketplace ideas and validator operations with the Pokoin community.',
                  style: TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onNewTopic,
            icon: Icon(signedIn ? Icons.add_comment_outlined : Icons.login),
            label: Text(signedIn ? 'New topic' : 'Login to post'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFACC15),
              foregroundColor: const Color(0xFF111827),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.items, required this.selected});

  final List<ForumCategory> items;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return _ForumPanel(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _CategoryChip(
            title: 'All discussions',
            description: 'Latest across Pokoin',
            icon: Icons.auto_awesome,
            active: selected == null,
            onTap: () => context.go('/forum'),
          ),
          for (final category in items)
            _CategoryChip(
              title: category.title,
              description: '${category.topicCount} topics',
              icon: _iconFor(category.iconName),
              active: selected == category.id,
              onTap: () => context.go('/forum/category/${category.id}'),
            ),
        ],
      ),
    );
  }
}

class _TopicList extends StatelessWidget {
  const _TopicList({required this.topics});

  final List<ForumTopic> topics;

  @override
  Widget build(BuildContext context) {
    return _ForumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Latest discussions',
            style: TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          if (topics.isEmpty)
            const _ForumEmpty()
          else
            for (final topic in topics) _TopicRow(topic: topic),
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.topic});

  final ForumTopic topic;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/forum/topic/${topic.id}'),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            _MiniAvatar(photoUrl: topic.authorPhotoUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${topic.authorName} · ${_formatDate(topic.updatedAt)}',
                    style:
                        const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _CountPill(
                icon: Icons.forum_outlined, value: '${topic.replyCount}'),
          ],
        ),
      ),
    );
  }
}

class _Replies extends StatelessWidget {
  const _Replies({required this.posts});

  final List<ForumPost> posts;

  @override
  Widget build(BuildContext context) {
    return _ForumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${posts.length} replies',
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          if (posts.isEmpty)
            const Text(
              'No replies yet. Be the first to continue the discussion.',
              style: TextStyle(color: Color(0xFFB8C4E6)),
            )
          else
            for (final post in posts)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AuthorLine(
                      name: post.authorName,
                      photoUrl: post.authorPhotoUrl,
                      date: post.createdAt,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      post.body,
                      style: const TextStyle(
                          color: Color(0xFFCBD5E1), height: 1.5),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ForumPanel extends StatelessWidget {
  const _ForumPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xE60B1020),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x55000000), blurRadius: 28, offset: Offset(0, 18)),
        ],
      ),
      child: child,
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.title,
    required this.description,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFFACC15).withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active
                ? const Color(0xFFFACC15)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFFACC15)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    description,
                    style:
                        const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorLine extends StatelessWidget {
  const _AuthorLine(
      {required this.name, required this.photoUrl, required this.date});

  final String name;
  final String? photoUrl;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MiniAvatar(photoUrl: photoUrl),
        const SizedBox(width: 10),
        Text(
          '$name · ${_formatDate(date)}',
          style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
        ),
      ],
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: photoUrl != null && photoUrl!.isNotEmpty
          ? Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _logoFallback(),
            )
          : _logoFallback(),
    );
  }

  Widget _logoFallback() {
    return Image.network(
      ProjectLinks.logo,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.person_outline,
        color: Color(0xFFFACC15),
        size: 18,
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFACC15).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFFFACC15)),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
                color: Color(0xFFFDE68A), fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ForumDialog extends StatelessWidget {
  const _ForumDialog(
      {required this.title, required this.body, required this.actions});

  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xF20B1020),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              body,
              const SizedBox(height: 22),
              Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: actions),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForumTextField extends StatelessWidget {
  const _ForumTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      decoration: _forumInputDecoration(label, icon),
    );
  }
}

InputDecoration _forumInputDecoration(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFF93A4C8)),
    prefixIcon: Icon(icon, color: const Color(0xFFFACC15)),
    filled: true,
    fillColor: const Color(0xFF111936),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFFACC15)),
    ),
  );
}

class _ForumLoading extends StatelessWidget {
  const _ForumLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFFFACC15)),
    );
  }
}

class _ForumError extends StatelessWidget {
  const _ForumError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(message, style: const TextStyle(color: Color(0xFFFF8A8A)));
  }
}

class _ForumEmpty extends StatelessWidget {
  const _ForumEmpty();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'No discussions yet. Start the first Pokoin community thread.',
      style: TextStyle(color: Color(0xFFB8C4E6)),
    );
  }
}

class _ForumTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _ForumTopBar();

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 820;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF2050816),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SizedBox(
                height: 68,
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => context.go('/forum'),
                      borderRadius: BorderRadius.circular(20),
                      child: const _ForumBrand(),
                    ),
                    const Spacer(),
                    if (!compact) ...[
                      const _ForumNavPill(),
                      const SizedBox(width: 12),
                    ],
                    _ForumTopButton(
                      label: 'Buy PKN',
                      icon: Icons.add_card_outlined,
                      primary: false,
                      onPressed: () => context.go('/buy'),
                    ),
                    const SizedBox(width: 10),
                    _ForumTopButton(
                      label: 'Wallet',
                      icon: Icons.account_balance_wallet_outlined,
                      primary: true,
                      onPressed: () => context.go('/wallet'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ForumBrand extends StatelessWidget {
  const _ForumBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF111936),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.network(
              ProjectLinks.logo,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.forum, color: Color(0xFFFACC15)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pokoin Forum',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Community and validators',
              style: TextStyle(
                color: Color(0xFF93A4C8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ForumNavPill extends StatelessWidget {
  const _ForumNavPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Row(
        children: [
          _ForumNavAction(label: 'Home', path: '/', icon: Icons.home_outlined),
          _ForumNavAction(
              label: 'Docs', path: '/docs', icon: Icons.article_outlined),
          _ForumNavAction(
              label: 'Market',
              path: '/marketplace',
              icon: Icons.storefront_outlined),
          _ForumNavAction(
              label: 'Scan', path: '/scan', icon: Icons.query_stats_outlined),
        ],
      ),
    );
  }
}

class _ForumNavAction extends StatelessWidget {
  const _ForumNavAction({
    required this.label,
    required this.path,
    required this.icon,
  });

  final String label;
  final String path;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => context.go(path),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFE2E8F0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFFACC15)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ForumTopButton extends StatelessWidget {
  const _ForumTopButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(compact && !primary ? '' : label),
      style: FilledButton.styleFrom(
        backgroundColor:
            primary ? const Color(0xFFFACC15) : const Color(0xFF111936),
        foregroundColor:
            primary ? const Color(0xFF111827) : const Color(0xFFE2E8F0),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: 13,
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

IconData _iconFor(String value) {
  switch (value) {
    case 'cards':
      return Icons.style_outlined;
    case 'token':
      return Icons.toll_outlined;
    case 'validators':
      return Icons.hub_outlined;
    case 'marketplace':
      return Icons.storefront_outlined;
    default:
      return Icons.forum_outlined;
  }
}

String _formatDate(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) {
    return 'now';
  }
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) {
    return 'now';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours}h ago';
  }
  return '${diff.inDays}d ago';
}

void _showForumMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: Colors.red),
  );
}
