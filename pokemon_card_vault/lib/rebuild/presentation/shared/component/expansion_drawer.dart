import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../controller/cardex_controller.dart';
import '../../../model/expansion_era.dart';
import '../../../model/marketplace_home.dart';

/// Pannello laterale globale; filtri e dati appartengono al controller Cardex.
class ExpansionDrawer extends StatefulWidget {
  const ExpansionDrawer(
      {super.key,
      required this.controller,
      required this.onSelect,
      required this.onCollection,
      required this.onClose});
  final CardexController controller;
  final ValueChanged<MarketplaceExpansion> onSelect;
  final VoidCallback onCollection, onClose;

  @override
  State<ExpansionDrawer> createState() => _ExpansionDrawerState();
}

class _ExpansionDrawerState extends State<ExpansionDrawer> {
  late final _search =
      TextEditingController(text: widget.controller.expansionQuery);
  final _expanded = <String>{};
  @override
  void didUpdateWidget(ExpansionDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _search.text = widget.controller.expansionQuery;
      _expanded.clear();
    }
  }

  @override
  Widget build(BuildContext context) => Drawer(
        width: math.min(440, MediaQuery.sizeOf(context).width * .94),
        child: SafeArea(
            child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final controller = widget.controller;
                  final searching = controller.expansionQuery.trim().isNotEmpty;
                  final groups = controller.visibleExpansionGroups;
                  final rows = <({
                    ExpansionEraGroup group,
                    MarketplaceExpansion? expansion
                  })>[
                    for (final group in groups) ...[
                      (group: group, expansion: null),
                      if (searching || _expanded.contains(group.id))
                        for (final expansion in group.expansions)
                          (group: group, expansion: expansion),
                    ],
                  ];
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                            child: Row(children: [
                              Expanded(
                                  child: Text('Espansioni',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge)),
                              IconButton(
                                  tooltip: 'Chiudi espansioni',
                                  onPressed: widget.onClose,
                                  icon: const Icon(Icons.close)),
                            ])),
                        const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                                'Scegli un’era o cerca un set per aprirlo nel Cardex.')),
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: TextField(
                              controller: _search,
                              onChanged: controller.setExpansionQuery,
                              decoration: InputDecoration(
                                labelText: 'Cerca espansione o era',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: searching
                                    ? IconButton(
                                        tooltip: 'Cancella filtro espansioni',
                                        onPressed: () {
                                          _search.clear();
                                          controller.setExpansionQuery('');
                                        },
                                        icon: const Icon(Icons.close))
                                    : null,
                              ),
                            )),
                        if (controller.ownershipKnown)
                          ListTile(
                              leading: const Icon(
                                  Icons.collections_bookmark_outlined),
                              title: const Text('Le mie carte'),
                              subtitle: Text(
                                  '${controller.collection.cards.length} carte · tutte le espansioni'),
                              selected: controller.viewingCollection,
                              onTap: widget.onCollection),
                        const Divider(height: 1),
                        Expanded(
                            child: controller.loadingExpansions
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : controller.expansionsError
                                    ? Center(
                                        child: Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Text(
                                                      'Impossibile caricare le espansioni.'),
                                                  TextButton(
                                                      onPressed: controller
                                                          .loadExpansions,
                                                      child: const Text(
                                                          'Riprova espansioni')),
                                                ])))
                                    : rows.isEmpty
                                        ? Center(
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.all(20),
                                                child: Text(searching
                                                    ? 'Nessuna espansione trovata.'
                                                    : 'Nessuna espansione disponibile.')))
                                        : ListView.builder(
                                            keyboardDismissBehavior:
                                                ScrollViewKeyboardDismissBehavior
                                                    .onDrag,
                                            itemCount: rows.length,
                                            itemBuilder: (context, index) {
                                              final row = rows[index];
                                              final expansion = row.expansion;
                                              if (expansion == null) {
                                                final open = searching ||
                                                    _expanded
                                                        .contains(row.group.id);
                                                return Semantics(
                                                    expanded: open,
                                                    child: ListTile(
                                                      key: ValueKey(
                                                          'era-${row.group.id}'),
                                                      title: Text(
                                                          row.group.title,
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700)),
                                                      subtitle: Text(
                                                          '${row.group.id} · ${row.group.expansions.length} espansioni'),
                                                      trailing: Icon(open
                                                          ? Icons.expand_less
                                                          : Icons.expand_more),
                                                      onTap: searching
                                                          ? null
                                                          : () => setState(() {
                                                                if (!_expanded
                                                                    .add(row
                                                                        .group
                                                                        .id)) {
                                                                  _expanded
                                                                      .remove(row
                                                                          .group
                                                                          .id);
                                                                }
                                                              }),
                                                    ));
                                              }
                                              final selected = !controller
                                                      .viewingCollection &&
                                                  controller.expansion?.slug ==
                                                      expansion.slug;
                                              return ListTile(
                                                key: ValueKey(
                                                    'expansion-${expansion.slug}'),
                                                contentPadding:
                                                    const EdgeInsets.only(
                                                        left: 32, right: 16),
                                                selected: selected,
                                                title: Text(expansion.name),
                                                subtitle: Text(
                                                    '${expansion.cardCount} carte'),
                                                trailing: selected
                                                    ? const Icon(Icons.check)
                                                    : null,
                                                onTap: () =>
                                                    widget.onSelect(expansion),
                                              );
                                            },
                                          )),
                      ]);
                })),
      );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}
