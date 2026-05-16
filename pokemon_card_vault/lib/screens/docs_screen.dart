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
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DocsHero(),
                  SizedBox(height: 22),
                  _GuidePanel(),
                  SiteFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocsHero extends StatelessWidget {
  const _DocsHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF111B3F), Color(0xFF0B1020)]),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pokoin Documentation',
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Run a PokoinPoS peer with Docker, join the public network, and verify the node health endpoints.',
            style: TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _GuidePanel extends StatelessWidget {
  const _GuidePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xE60B1020),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DocSection(
            eyebrow: 'Requirements',
            title: 'Before you start',
            body:
                'Install Docker and Docker Compose on a Linux VPS or local machine. Open the peer P2P port you choose, for example 43001. The operator token is optional and only needed for guarded local actions.',
          ),
          _CodeBlock(
            text:
                'docker --version\n'
                'docker compose version',
          ),
          _DocSection(
            eyebrow: 'Step 1',
            title: 'Prepare an environment file',
            body:
                'Copy the peer template and edit the values for your node name, local ports and join host. Leave POKOINPOS_OPERATOR_TOKEN empty unless you need protected operator actions.',
          ),
          _CodeBlock(
            text:
                'cp deploy/env/peer.env.example deploy/env/my-peer.env\n'
                'nano deploy/env/my-peer.env',
          ),
          _DocSection(
            eyebrow: 'Important values',
            title: 'Minimal peer configuration',
            body:
                'Use a unique peer name and ports. POKOINPOS_ADVERTISE_HOST must be reachable by other peers. Join host, bootstrap peers, refresh interval, EVM chain ID and network ID are supplied by the public bootstrap manifest.',
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
            eyebrow: 'Step 2',
            title: 'Start the Docker peer',
            body:
                'The helper script pulls the published Docker image and starts the peer with auto-update enabled. You can also use docker compose directly.',
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
          _DocSection(
            eyebrow: 'Step 3',
            title: 'Verify your node',
            body:
                'Check health, readiness and chain status on the local ops port you configured. A ready node should report chain status and peer connectivity.',
          ),
          _CodeBlock(
            text:
                'curl http://localhost:8081/health\n'
                'curl http://localhost:8081/ready\n'
                'curl http://localhost:8081/chain/status',
          ),
          _DocSection(
            eyebrow: 'Step 4',
            title: 'Bootstrap eligibility',
            body:
                'New public nodes spend 14 days in vetting and must stay online at least 95% of that window. After vetting they are regular peers until they are 365 days old. Only then can they become bootstrap nodes, with at least 94% observed uptime over the last 365 days, confirmed by at least 3 other peers.',
          ),
          _CodeBlock(
            text:
                'Current Oracle bootstrap peers:\n'
                '92.5.153.117:43000  # pokoinpos-vm, grandfathered bootstrap\n'
                '130.162.242.213:43001  # pokoin-vm2, grandfathered bootstrap\n\n'
                'Current Oracle vetting peers:\n'
                '141.147.62.244:43000  # pokoin-vm3\n'
                '92.5.23.133:43001  # pokoin-vm4',
          ),
          _CodeBlock(
            text:
                'curl https://pokoin.com/bootstrap-peers.json\n'
                'curl http://localhost:8081/chain/bootstrap',
          ),
          _DocSection(
            eyebrow: 'Runtime updates',
            title: 'How nodes receive blockchain updates',
            body:
                'The live Oracle nodes run the Docker Hub image newisdom/pokoinpos-peer:latest. Code changes in the repository become live only after the multi-architecture Docker image is pushed; Watchtower then pulls and restarts each node automatically.',
          ),
          _CodeBlock(
            text:
                'make test\n'
                'make docker-push\n'
                'docker buildx imagetools inspect newisdom/pokoinpos-peer:latest',
          ),
          _DocSection(
            eyebrow: 'Step 5',
            title: 'Operate safely',
            body:
                'Persist node state with POKOINPOS_STATE_HOST_PATH. If you enable POKOINPOS_OPERATOR_TOKEN, keep it secret. Expose public RPC only through a hardened gateway and do not publish node-local operator endpoints directly.',
          ),
        ],
      ),
    );
  }
}

class _DocSection extends StatelessWidget {
  const _DocSection({
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final String eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFFACC15),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
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
      decoration: BoxDecoration(
        color: const Color(0xF2050816),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
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
