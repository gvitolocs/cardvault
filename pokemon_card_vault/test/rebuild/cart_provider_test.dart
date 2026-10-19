// Fakes limitati ai contratti SDK usati dal DAO; nessun accesso Firebase reale.
// ignore_for_file: subtype_of_sealed_class

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pokoin/rebuild/model/cart_item.dart';
import 'package:pokoin/rebuild/provider/cart_codec.dart';
import 'package:pokoin/rebuild/provider/cart_local_provider.dart';
import 'package:pokoin/rebuild/provider/cart_remote_provider.dart';
import 'fixtures/cart_fixtures.dart';

Map<String, dynamic> legacyRow(String id) => {
      'card': {
        'id': '24',
        'name': 'Carta salvata',
        'imageUrl': '',
        'set': 'Base',
        'number': '1',
        'unknownCardField': 'preserved'
      },
      'quantity': 2,
      'listingId': id,
      'sellerUid': 'seller-1',
      'sellerName': 'Venditore',
      'condition': 'NM',
      'language': 'IT',
      'unitPricePkn': 42.5,
      'quantityAvailable': 8,
      'source': 'cardtrader',
      'sourceListingId': 'ct-987',
      'sourceMetadata': {'shipping': 'kept'},
      'nftAvailable': true,
    };

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
}

class _Auth extends Fake implements FirebaseAuth {
  User? user = _User('alice');
  @override
  User? get currentUser => user;
}

class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.value);
  final Map<String, dynamic>? value;
  @override
  Map<String, dynamic>? data() => value;
}

class _Reference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.db);
  final _Firestore db;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      [GetOptions? options]) async {
    expect(options!.source, Source.server);
    return _Snapshot(db.data);
  }
}

class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db);
  final _Firestore db;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    db.requestedUid = path;
    return _Reference(db);
  }
}

class _Transaction extends Fake implements Transaction {
  _Transaction(this.db);
  final _Firestore db;
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
      DocumentReference<T> reference) async {
    return _Snapshot(db.data) as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(DocumentReference<T> reference, T data,
      [SetOptions? options]) {
    expect(options!.merge, isTrue);
    db.data = {...?db.data, ...data as Map<String, dynamic>};
    return this;
  }
}

class _Firestore extends Fake implements FirebaseFirestore {
  Map<String, dynamic>? data;
  String? requestedUid;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    expect(path, 'user_carts');
    return _Collection(this);
  }

  @override
  Future<T> runTransaction<T>(TransactionHandler<T> transactionHandler,
          {Duration timeout = const Duration(seconds: 30),
          int maxAttempts = 5}) =>
      transactionHandler(_Transaction(this));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Hive DAO', () {
    late Directory directory;
    late HiveCartProvider provider;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('pokoin-cart-test-');
      Hive.init(directory.path);
      provider = HiveCartProvider(initialize: () async {});
    });
    tearDown(() async {
      await Hive.close();
      final temporaryRoot = Directory.systemTemp.absolute.path;
      if (!directory.absolute.path.startsWith(
          '$temporaryRoot${Platform.pathSeparator}pokoin-cart-test-')) {
        throw StateError('Unexpected test cleanup directory');
      }
      await directory.delete(recursive: true);
    });

    test(
        'imports scoped legacy data, preserves metadata and does not modify old boxes',
        () async {
      final old = await Hive.openBox<Map>('cart_items_alice');
      await old.put('offer', legacyRow('offer'));
      final snapshot = await provider.read('alice');
      expect(snapshot.items.single.quantity, 2);
      expect(snapshot.items.single.listing.pricePkn, 42.5);
      final encoded =
          CartCodec.encodeItem(snapshot.items.single.withQuantity(3));
      expect(encoded['sellerUid'], 'seller-1');
      expect(encoded['sourceListingId'], 'ct-987');
      expect(encoded['sourceMetadata'], {'shipping': 'kept'});
      expect(encoded['nftAvailable'], isTrue);
      expect((encoded['card'] as Map)['unknownCardField'], 'preserved');
      expect(snapshot.pending.keys, ['offer']);
      await provider.write('alice', snapshot);
      await Hive.close();
      final restored = await provider.read('alice');
      expect(restored.items.single.quantity, 2);
      expect(restored.pending['offer']!.item!.quantity, 2);
      expect((await Hive.openBox<Map>('cart_items_alice')).get('offer'),
          legacyRow('offer'));
      await provider.write('alice', CartSnapshot());
      expect((await provider.read('alice')).items, isEmpty,
          reason: 'An empty saved cart does not reimport the legacy box');
    });

    test(
        'guest fallback is isolated from accounts, and scoped keys have no collisions',
        () async {
      final old = await Hive.openBox<Map>('cart_items');
      await old.put('offer', legacyRow('guest'));
      expect((await provider.read(null)).items.single.listing.id, 'guest');
      expect((await provider.read('alice')).items, isEmpty);
      await provider.write(null, CartSnapshot());
      expect((await provider.read(null)).items, isEmpty);
      expect(provider.boxName('guest'), isNot(provider.boxName(null)));
      expect(provider.boxName('Alice'), isNot(provider.boxName('alice')));
      expect(provider.boxName('a:b'), isNot(provider.boxName('a_b')));
    });

    test(
        'snapshot persists removals and rejects damaged saves instead of replacing them',
        () async {
      await provider.write(
          'alice', CartSnapshot(pending: {'gone': const CartEdit(null)}));
      expect((await provider.read('alice')).pending['gone']!.item, isNull);
      final box = await Hive.openBox<Map>(provider.boxName('alice'));
      await box.put('snapshot', {'version': 999});
      await expectLater(provider.read('alice'), throwsFormatException);
      expect(box.get('snapshot'), {'version': 999});
    });
  });

  test('remote patches are absolute/idempotent and retain unknown legacy rows',
      () async {
    final unknown = {
      'card': {'id': '48', 'name': 'Catalog only'},
      'quantity': 1
    };
    final db = _Firestore()
      ..data = {
        'items': [legacyRow('a'), legacyRow('b'), unknown],
        'otherField': 'kept'
      };
    final auth = _Auth();
    final provider = FirestoreCartProvider(firestore: db, auth: auth);
    expect((await provider.read('alice')).map((item) => item.listing.id),
        ['a', 'b']);
    final patch = {
      'a': CartEdit(cartRow('a', quantity: 3)),
      'b': const CartEdit(null)
    };
    for (var retry = 0; retry < 3; retry++) {
      final items = await provider.apply('alice', patch);
      expect(items.single.quantity, 3);
    }
    expect(db.requestedUid, 'alice');
    expect(db.data!['otherField'], 'kept');
    expect(db.data!['updatedAt'], isA<FieldValue>());
    expect(db.data!['items'], hasLength(2));
    expect((db.data!['items'] as List).last, unknown);
    auth.user = _User('bob');
    expect(() => provider.apply('alice', patch), throwsStateError);
    await expectLater(provider.read('alice'), throwsStateError);
  });

  test(
      'remote malformed payloads and more than 100 rows fail without replacing data',
      () async {
    final db = _Firestore()..data = {'items': 'damaged'};
    final provider = FirestoreCartProvider(firestore: db, auth: _Auth());
    await expectLater(provider.apply('alice', {'a': CartEdit(cartRow('a'))}),
        throwsFormatException);
    expect(db.data!['items'], 'damaged');
    db.data = {
      'items': [for (var i = 0; i < 100; i++) legacyRow('$i')]
    };
    await expectLater(
        provider.apply('alice', {'new': CartEdit(cartRow('new'))}),
        throwsStateError);
    expect(db.data!['items'], hasLength(100));
  });
}
