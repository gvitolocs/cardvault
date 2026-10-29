import 'package:flutter/material.dart';
import '../../constants/seller_country_constants.dart';
import '../../controller/shipping_addresses_controller.dart';
import '../../model/shipping_address.dart';

class ShippingAddressesScreen extends StatefulWidget {
  const ShippingAddressesScreen({super.key, required this.controller});
  final ShippingAddressesController controller;
  @override
  State<ShippingAddressesScreen> createState() =>
      _ShippingAddressesScreenState();
}

class _ShippingAddressesScreenState extends State<ShippingAddressesScreen> {
  int? _loadedScope;
  @override
  void initState() {
    super.initState();
    _loadedScope = widget.controller.scopeRevision;
    widget.controller.load();
  }

  void _edit([ShippingAddress? address]) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddressEditor(
          controller: widget.controller,
          address: address ??
              ShippingAddress(isDefault: widget.controller.items.isEmpty)));
  Future<void> _remove(ShippingAddress address) async {
    final scope = widget.controller.scopeRevision;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Rimuovere questo indirizzo?'),
                content: const Text(
                    'Non sarà più disponibile tra gli indirizzi del tuo account.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annulla')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Rimuovi'))
                ]));
    if (accepted == true &&
        mounted &&
        scope == widget.controller.scopeRevision) {
      await widget.controller.remove(address.id);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Indirizzi di spedizione')),
      body: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final c = widget.controller;
            if (c.authenticated && _loadedScope != c.scopeRevision) {
              final scope = c.scopeRevision;
              _loadedScope = scope;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && scope == c.scopeRevision) c.load();
              });
            }
            if (!c.authenticated) {
              return const Center(
                  child: Text('Accedi per gestire i tuoi indirizzi.'));
            }
            return ListView(padding: const EdgeInsets.all(20), children: [
              const Text(
                  'L’indirizzo predefinito fornisce il Paese iniziale per i nuovi listing. Il Paese nel modulo di vendita resta modificabile.'),
              const SizedBox(height: 16),
              if (c.loading || c.busy) const LinearProgressIndicator(),
              if (c.error != null) ...[
                Text(c.error!),
                TextButton(
                    onPressed: c.busy || c.loading ? null : c.load,
                    child: const Text('Ricarica indirizzi'))
              ],
              if (c.loaded && c.items.isEmpty)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('Non hai ancora salvato indirizzi.')),
              for (final address in c.items)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                  address.label.isEmpty
                                      ? address.fullName
                                      : address.label,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              if (address.isDefault)
                                const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Chip(
                                        label: Text('Predefinito'),
                                        avatar: Icon(Icons.check, size: 18))),
                              Text([
                                address.fullName,
                                address.addressLine1,
                                address.addressLine2,
                                '${address.postalCode} ${address.city}',
                                sellerCountryNames[address.countryCode] ??
                                    address.countryCode,
                                address.phoneNumber
                              ].where((s) => s.trim().isNotEmpty).join('\n')),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, children: [
                                if (!address.isDefault)
                                  TextButton(
                                      onPressed: c.busy || !c.loaded
                                          ? null
                                          : () => c.setDefault(address),
                                      child: const Text('Rendi predefinito')),
                                TextButton(
                                    onPressed: c.busy || !c.loaded
                                        ? null
                                        : () => _edit(address),
                                    child: const Text('Modifica')),
                                TextButton(
                                    onPressed: c.busy || !c.loaded
                                        ? null
                                        : () => _remove(address),
                                    child: const Text('Rimuovi')),
                              ]),
                            ]))),
              const SizedBox(height: 12),
              FilledButton.icon(
                  onPressed:
                      c.busy || c.loading || !c.loaded ? null : () => _edit(),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Aggiungi indirizzo')),
            ]);
          }));
}

class _AddressEditor extends StatefulWidget {
  const _AddressEditor({required this.controller, required this.address});
  final ShippingAddressesController controller;
  final ShippingAddress address;
  @override
  State<_AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends State<_AddressEditor> {
  final _form = GlobalKey<FormState>();
  late final int _scope = widget.controller.scopeRevision;
  late final _fields = {
    for (final e in widget.address.toJson().entries)
      if (e.value is String)
        e.key: TextEditingController(text: e.value as String)
  };
  late String _country =
      sellerShipFromCountries.containsKey(widget.address.countryCode)
          ? widget.address.countryCode
          : '';
  late bool _default = widget.address.isDefault;
  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate() ||
        _scope != widget.controller.scopeRevision) {
      return;
    }
    final address = ShippingAddress.fromJson({
      for (final e in _fields.entries) e.key: e.value.text,
      'id': widget.address.id,
      'countryCode': _country,
      'isDefault': _default
    });
    if (await widget.controller.save(address) && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (_scope != widget.controller.scopeRevision ||
            !widget.controller.authenticated) {
          return const SafeArea(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'Account cambiato. Riapri gli indirizzi dal Profilo.')));
        }
        return SafeArea(
            child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
                child: Form(
                    key: _form,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              widget.address.id.isEmpty
                                  ? 'Nuovo indirizzo'
                                  : 'Modifica indirizzo',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 16),
                          for (final e in const {
                            'label': 'Etichetta (facoltativa)',
                            'fullName': 'Nome e cognome',
                            'addressLine1': 'Indirizzo',
                            'addressLine2':
                                'Interno / seconda riga (facoltativa)',
                            'postalCode': 'CAP',
                            'city': 'Città',
                            'phoneNumber': 'Telefono (facoltativo)'
                          }.entries)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: TextFormField(
                                    controller: _fields[e.key],
                                    enabled: !widget.controller.busy,
                                    maxLength: e.key == 'label' ? 60 : 160,
                                    decoration:
                                        InputDecoration(labelText: e.value),
                                    validator: (value) => const [
                                              'fullName',
                                              'addressLine1',
                                              'postalCode',
                                              'city'
                                            ].contains(e.key) &&
                                            (value ?? '').trim().isEmpty
                                        ? 'Campo obbligatorio'
                                        : null)),
                          DropdownButtonFormField<String>(
                              initialValue: _country,
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(labelText: 'Paese'),
                              items: sellerShipFromCountries.entries
                                  .map((e) => DropdownMenuItem(
                                      value: e.key, child: Text(e.value)))
                                  .toList(),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                      ? 'Seleziona il Paese'
                                      : null,
                              onChanged: widget.controller.busy
                                  ? null
                                  : (value) =>
                                      setState(() => _country = value ?? '')),
                          CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Indirizzo predefinito'),
                              value: _default,
                              onChanged: widget.controller.busy
                                  ? null
                                  : (value) => setState(
                                      () => _default = value ?? false)),
                          if (widget.controller.error != null)
                            Text(widget.controller.error!),
                          FilledButton(
                              onPressed: widget.controller.busy ||
                                      !widget.controller.loaded
                                  ? null
                                  : _save,
                              child: Text(widget.controller.busy
                                  ? 'Salvataggio…'
                                  : 'Salva indirizzo')),
                        ]))));
      });
}
