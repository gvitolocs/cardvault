import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/project_links.dart';
import '../widgets/site_footer.dart';

class DocsScreen extends StatelessWidget {
  const DocsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: const _DocsTopBar(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.35,
            colors: [Color(0x2638BDF8), Color(0x00050816)],
          ),
        ),
        child: const _DocsLayout(),
      ),
    );
  }
}

class _DocsLayout extends StatefulWidget {
  const _DocsLayout();

  @override
  State<_DocsLayout> createState() => _DocsLayoutState();
}

class _DocsLayoutState extends State<_DocsLayout> {
  static const items = [
    _DocsNavItem('Overview', 'How the network works', Icons.hub_outlined),
    _DocsNavItem('Network roles', 'Validators, peers, vetting', Icons.groups_2_outlined),
    _DocsNavItem('Consensus', 'Permissioned PoS lifecycle', Icons.verified_outlined),
    _DocsNavItem('Run a node', 'Docker peer setup', Icons.terminal_outlined),
    _DocsNavItem('Wallets', 'PKN balances and transfers', Icons.account_balance_wallet_outlined),
    _DocsNavItem('Operations', 'Health checks and upgrades', Icons.monitor_heart_outlined),
    _DocsNavItem('Security', 'Keys, endpoints, recovery', Icons.shield_outlined),
    _DocsNavItem('FAQ', 'Common questions', Icons.help_outline),
  ];

  late final List<GlobalKey> _sectionKeys =
      List<GlobalKey>.generate(items.length, (_) => GlobalKey());
  int _selectedIndex = 0;

  Future<void> _scrollToSection(int index) async {
    setState(() => _selectedIndex = index);
    final context = _sectionKeys[index].currentContext;
    if (context == null) {
      return;
    }
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(wide ? 28 : 18, 22, wide ? 28 : 18, 44),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 280,
                          child: _DocsSidebar(
                            items: items,
                            selectedIndex: _selectedIndex,
                            onSelect: _scrollToSection,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _DocsContent(
                            compact: !wide,
                            sectionKeys: _sectionKeys,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MobileDocsNav(
                          items: items,
                          selectedIndex: _selectedIndex,
                          onSelect: _scrollToSection,
                        ),
                        const SizedBox(height: 18),
                        _DocsContent(
                          compact: true,
                          sectionKeys: _sectionKeys,
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _DocsNavItem {
  const _DocsNavItem(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

class _DocsSidebar extends StatelessWidget {
  const _DocsSidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_DocsNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE60B1020),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.network(
                ProjectLinks.logo,
                width: 34,
                height: 34,
                filterQuality: FilterQuality.none,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.article_outlined, color: Color(0xFFFACC15)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Pokoin Docs',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Start here',
            style: TextStyle(
              color: Color(0xFFFACC15),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < items.length; i++)
            _SidebarButton(
              item: items[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
          const SizedBox(height: 18),
          const _Callout(
            title: 'Need live status?',
            body:
                'Use PokoinScan and the network health page to verify blocks, peers, RPC readiness, and reserve proof.',
          ),
        ],
      ),
    );
  }
}

class _MobileDocsNav extends StatelessWidget {
  const _MobileDocsNav({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_DocsNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xE60B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < items.length; i++)
            ActionChip(
              onPressed: () => onSelect(i),
              avatar: Icon(
                items[i].icon,
                size: 16,
                color: i == selectedIndex
                    ? const Color(0xFF111827)
                    : const Color(0xFFFACC15),
              ),
              label: Text(items[i].label),
              backgroundColor:
                  i == selectedIndex ? const Color(0xFFFACC15) : const Color(0xFF111936),
              labelStyle: TextStyle(
                color: i == selectedIndex ? const Color(0xFF111827) : Colors.white,
                fontWeight: FontWeight.w800,
              ),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _DocsNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFFACC15)
                  : Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFACC15)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 20,
                  color: selected
                      ? const Color(0xFF111827)
                      : const Color(0xFFFACC15),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                          color: selected ? const Color(0xFF111827) : Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.description,
                        style: TextStyle(
                          color: selected
                              ? const Color(0xCC111827)
                              : const Color(0xFF93A4C8),
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DocsContent extends StatelessWidget {
  const _DocsContent({
    required this.compact,
    required this.sectionKeys,
  });

  final bool compact;
  final List<GlobalKey> sectionKeys;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: sectionKeys[0],
          child: _HeroArticle(compact: compact),
        ),
        const SizedBox(height: 18),
        KeyedSubtree(
          key: sectionKeys[1],
          child: const _DocArticle(
            eyebrow: 'Network roles',
            title: 'Validators, peers, and vetting nodes',
            body:
                'PokoinPoS is a permissioned network. The bootstrap set introduces new peers, vetting nodes prove reliability, and validators maintain the canonical chain. This keeps participation open to approved operators while avoiding anonymous validator churn.',
            children: [
              _InfoGrid(
                cards: [
                  _InfoCardData(
                    'Bootstrap peers',
                    'Long-lived entry points that publish peer information and help new nodes discover the network.',
                    Icons.route_outlined,
                  ),
                  _InfoCardData(
                    'Vetting nodes',
                    'New public nodes spend time proving uptime and network behavior before becoming regular peers.',
                    Icons.hourglass_bottom_outlined,
                  ),
                  _InfoCardData(
                    'Validators',
                    'Approved staking nodes that participate in block production and maintain consensus.',
                    Icons.security_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        KeyedSubtree(
          key: sectionKeys[2],
          child: const _DocArticle(
            eyebrow: 'Consensus',
            title: 'Permissioned Proof of Stake lifecycle',
            body:
                'The network uses Proof of Stake rules within a permissioned operator set. Stake and validator identity are tied to known nodes, while node health and peer observations decide when infrastructure is trusted enough for bootstrap responsibilities.',
            children: [
              _StepList(
                steps: [
                  _StepData('1', 'Discovery', 'A peer starts from the public bootstrap manifest and connects to known network nodes.'),
                  _StepData('2', 'Vetting', 'The node stays online and observable for the vetting window.'),
                  _StepData('3', 'Participation', 'Healthy approved nodes exchange chain data and can become validator infrastructure.'),
                  _StepData('4', 'Bootstrap maturity', 'After long-term uptime, a node can qualify as a bootstrap candidate.'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        KeyedSubtree(
          key: sectionKeys[3],
          child: const _DocArticle(
            eyebrow: 'Run a node',
            title: 'Start a PokoinPoS peer with Docker',
            body:
                'Operators run the published peer image with a local environment file. The node stores chain state on disk, advertises a reachable host and port, and exposes local health endpoints for monitoring.',
            children: [
              _DocSection(
                title: 'Requirements',
                body:
                    'Install Docker and Docker Compose on a Linux VPS or local machine. Open the peer P2P port you choose, for example 43001. The operator token is optional and only needed for guarded local actions.',
              ),
              _CodeBlock(text: 'docker --version\ndocker compose version'),
              _DocSection(
                title: 'Prepare an environment file',
                body:
                    'Copy the peer template and edit the values for your node name, local ports and join host.',
              ),
              _CodeBlock(
                text:
                    'cp deploy/env/peer.env.example deploy/env/my-peer.env\n'
                    'nano deploy/env/my-peer.env',
              ),
              _CodeBlock(
                text:
                    'PEER_NAME=pokoinpos-my-peer\n'
                    'POKOINPOS_LISTEN_PORT=43001\n'
                    'POKOINPOS_ADVERTISE_HOST=example.duckdns.com\n'
                    'POKOINPOS_OPS_PORT=8081\n'
                    'POKOINPOS_BOOTSTRAP_MANIFEST_URL=https://pokoin.com/bootstrap-peers.json\n'
                    'POKOINPOS_OPERATOR_TOKEN=',
              ),
              _DocSection(
                title: 'Start the peer',
                body:
                    'The helper script pulls the Docker image and starts the peer. You can also use Docker Compose directly.',
              ),
              _CodeBlock(
                text:
                    'chmod +x deploy/scripts/docker-peer-up.sh\n'
                    './deploy/scripts/docker-peer-up.sh deploy/env/my-peer.env',
              ),
              _CodeBlock(
                text:
                    'docker compose --env-file deploy/env/my-peer.env \\\n'
                    '  -f docker-compose.peer.yml up -d --remove-orphans',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        KeyedSubtree(
          key: sectionKeys[4],
          child: const _DocArticle(
            eyebrow: 'Wallets',
            title: 'PKN balances, usernames, and wallet linking',
            body:
                'Pokoin separates site account balance from connected wallet balance. Username transfers move site balance instantly. MetaMask links a 0x wallet for top-ups, on-chain withdrawals, and native PKN visibility.',
            children: [
              _InfoGrid(
                cards: [
                  _InfoCardData(
                    'Account balance',
                    'Used for marketplace purchases and username transfers inside Pokoin.',
                    Icons.account_circle_outlined,
                  ),
                  _InfoCardData(
                    'Connected wallet',
                    'Your MetaMask or EVM wallet address linked to the same Pokoin account.',
                    Icons.wallet_outlined,
                  ),
                  _InfoCardData(
                    'Username transfer',
                    'Send PKN to a user handle without needing their wallet address.',
                    Icons.alternate_email,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        KeyedSubtree(
          key: sectionKeys[5],
          child: const _DocArticle(
            eyebrow: 'Operations',
            title: 'Health checks, bootstrap status, and upgrades',
            body:
                'Node operators should monitor local health endpoints and the public bootstrap manifest. Live Oracle nodes run the Docker Hub image newisdom/pokoinpos-peer:latest, so production updates go live after a multi-architecture image push.',
            children: [
              _CodeBlock(
                text:
                    'curl http://localhost:8081/health\n'
                    'curl http://localhost:8081/ready\n'
                    'curl http://localhost:8081/chain/status\n'
                    'curl https://pokoin.com/bootstrap-peers.json',
              ),
              _CodeBlock(
                text:
                    'make test\n'
                    'make docker-push\n'
                    'docker buildx imagetools inspect newisdom/pokoinpos-peer:latest',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        KeyedSubtree(
          key: sectionKeys[6],
          child: const _DocArticle(
            eyebrow: 'Security',
            title: 'Safe operation guidelines',
            body:
                'Keep validator keys, wallet private keys, and operator tokens out of source control. Expose public RPC only through a hardened gateway and never publish node-local operator endpoints directly.',
            children: [
              _Callout(
                title: 'Production rule',
                body:
                    'A node can recover from container restarts only if its state path is persisted. Set POKOINPOS_STATE_HOST_PATH to durable disk storage.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        KeyedSubtree(
          key: sectionKeys[7],
          child: const _DocArticle(
            eyebrow: 'FAQ',
            title: 'Common questions',
            body:
                'These are the quick answers most operators and users need before joining the network.',
            children: [
              _FaqItem(
                question: 'Can any node become a bootstrap node?',
                answer:
                    'No. A public node must mature over time, maintain high uptime, and be confirmed by other peers before it can qualify.',
              ),
              _FaqItem(
                question: 'Why does MetaMask open its own browser on mobile?',
                answer:
                    'Mobile Chrome and Safari do not expose the injected wallet provider. MetaMask actions happen inside the MetaMask in-app browser unless WalletConnect is added.',
              ),
              _FaqItem(
                question: 'Where do I inspect live chain status?',
                answer:
                    'Use PokoinScan, the RPC health endpoints, and the bootstrap manifest linked from this page.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SiteFooter(),
      ],
    );
  }
}

class _HeroArticle extends StatelessWidget {
  const _HeroArticle({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 22 : 32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111B3F), Color(0xFF0B1020)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'POKOIN NETWORK',
            style: TextStyle(
              color: Color(0xFFFACC15),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'How the Pokoin network works',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 34 : 48,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'PokoinPoS is the native blockchain behind PKN. It combines a permissioned Proof-of-Stake validator set, public peer discovery, node vetting, and EVM-compatible wallet access so users can move PKN through usernames, wallets, and marketplace flows.',
            style: TextStyle(
              color: Color(0xFFB8C4E6),
              fontSize: 16,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 22),
          const _InfoGrid(
            cards: [
              _InfoCardData(
                'Users',
                'Hold site balances, link wallets, buy cards, and send PKN by username.',
                Icons.person_outline,
              ),
              _InfoCardData(
                'Peers',
                'Discover each other through bootstrap manifests and exchange chain state.',
                Icons.device_hub_outlined,
              ),
              _InfoCardData(
                'Validators',
                'Produce blocks in the approved PoS network and keep the ledger consistent.',
                Icons.verified_user_outlined,
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _Callout(
            title: 'Mental model',
            body:
                'Think of Pokoin as three layers: account UX for users, native PKN settlement on PokoinPoS, and operational infrastructure that keeps peers discoverable and healthy.',
          ),
        ],
      ),
    );
  }
}

class _DocArticle extends StatelessWidget {
  const _DocArticle({
    required this.eyebrow,
    required this.title,
    required this.body,
    this.children = const [],
  });

  final String eyebrow;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: const Color(0xE60B1020),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DocSection(
            eyebrow: eyebrow,
            title: title,
            body: body,
          ),
          ...children,
        ],
      ),
    );
  }
}

class _DocSection extends StatelessWidget {
  const _DocSection({
    this.eyebrow,
    required this.title,
    required this.body,
  });

  final String? eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow!.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFFFACC15),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _InfoCardData {
  const _InfoCardData(this.title, this.body, this.icon);

  final String title;
  final String body;
  final IconData icon;
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.cards});

  final List<_InfoCardData> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
              SizedBox(
                width: wide
                    ? (constraints.maxWidth - 24) / 3
                    : constraints.maxWidth,
                child: _InfoCard(card: card),
              ),
          ],
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.card});

  final _InfoCardData card;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(card.icon, color: const Color(0xFFFACC15)),
          const SizedBox(height: 12),
          Text(
            card.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            card.body,
            style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _StepData {
  const _StepData(this.number, this.title, this.body);

  final String number;
  final String title;
  final String body;
}

class _StepList extends StatelessWidget {
  const _StepList({required this.steps});

  final List<_StepData> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final step in steps)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFFACC15),
                  child: Text(
                    step.number,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.body,
                        style: const TextStyle(
                          color: Color(0xFFB8C4E6),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x22FACC15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x66FACC15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, color: Color(0xFFFACC15)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(color: Color(0xFFE2E8F0), height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  const _FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            answer,
            style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF050816),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          color: Color(0xFFE2E8F0),
          fontFamily: 'monospace',
          height: 1.45,
        ),
      ),
    );
  }
}

class _DocsTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _DocsTopBar();

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xF2050816)),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                children: [
                  Image.network(
                    ProjectLinks.logo,
                    width: 42,
                    height: 42,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.article_outlined, color: Color(0xFFFACC15)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Documentation',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  TextButton(onPressed: () => context.go('/'), child: const Text('Home')),
                  TextButton(onPressed: () => context.go('/forum'), child: const Text('Forum')),
                  FilledButton(
                    onPressed: () => context.go('/wallet'),
                    child: const Text('Wallet'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
