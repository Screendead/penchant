import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'firestore_index_coverage.dart';

// The emulators ignore composite indexes, so a query whose index the file
// lacks passes every other check and fails in production with
// failed-precondition.

final Map<String, dynamic> _indexFile =
    jsonDecode(File('firestore.indexes.json').readAsStringSync())
        as Map<String, dynamic>;

final List<Map<String, dynamic>> _indexes =
    (_indexFile['indexes'] as List<dynamic>).cast<Map<String, dynamic>>();

Map<String, dynamic> _index(String collection, List<List<String>> fields) =>
    <String, dynamic>{
      'collectionGroup': collection,
      'queryScope': 'COLLECTION',
      'fields': <Map<String, String>>[
        for (final List<String> f in fields)
          <String, String>{
            'fieldPath': f[0],
            if (f[1] == 'CONTAINS') 'arrayConfig': f[1] else 'order': f[1],
          },
      ],
    };

QueryShape _shape({
  String? collection = 'activities',
  List<Filter> filters = const <Filter>[],
  List<Order> orders = const <Order>[],
}) => QueryShape(
  collection: collection,
  location: 'test',
  filters: filters,
  orders: orders,
);

Filter _eq(String field) => (field: field, kind: FilterKind.equality);
Filter _range(String field) => (field: field, kind: FilterKind.inequality);
Filter _contains(String field) => (field: field, kind: FilterKind.contains);
Order _asc(String field) => (field: field, descending: false);
Order _desc(String field) => (field: field, descending: true);

void main() {
  group('lib/ against firestore.indexes.json', () {
    final QueryScan scan = scanQueries(Directory('lib'));

    test('the scan reads every query clause', () {
      expect(scan.unreadable, isEmpty);
    });

    test('the scan finds the composite queries', () {
      final Iterable<QueryShape> composite = scan.shapes.where(
        (QueryShape shape) => compositeNeed(shape) != null,
      );
      expect(
        composite.map((QueryShape s) => s.location),
        containsAll(<Matcher>[
          contains('vice_list_provider.dart'),
          contains('vice_activity_day_provider.dart'),
          contains('vice_activity_history_provider.dart'),
        ]),
      );
    });

    test('automatic single-field indexes stay on', () {
      expect(_indexFile['fieldOverrides'] ?? <dynamic>[], isEmpty);
    });

    test('every composite query has an index', () {
      expect(uncoveredQueries(scan.shapes, _indexes), isEmpty);
    });

    // functions/ is not scanned: its one composite query (monthlySummaries,
    // activities by ownerID and a createdAt range, sorted desc) rides the
    // activities (ownerID, createdAt DESC) entry lib/ also uses.
    test('every index serves a query in lib/', () {
      for (final Map<String, dynamic> index in _indexes) {
        final bool used = scan.shapes.any((QueryShape shape) {
          final CompositeNeed? need = compositeNeed(shape);
          return need != null &&
              shape.collection != null &&
              serves(index, shape.collection!, need);
        });
        expect(used, isTrue, reason: 'no query uses $index');
      }
    });

    test('removing any used index fails the check', () {
      for (int i = 0; i < _indexes.length; i++) {
        final List<Map<String, dynamic>> without = <Map<String, dynamic>>[
          ..._indexes.sublist(0, i),
          ..._indexes.sublist(i + 1),
        ];
        final bool used = scan.shapes.any((QueryShape shape) {
          final CompositeNeed? need = compositeNeed(shape);
          return need != null &&
              shape.collection != null &&
              serves(_indexes[i], shape.collection!, need);
        });
        if (used) {
          expect(
            uncoveredQueries(scan.shapes, without),
            isNotEmpty,
            reason: 'index $i serves a query',
          );
        }
      }
    });
  });

  group('compositeNeed', () {
    test('equality filters alone merge single-field indexes', () {
      expect(
        compositeNeed(_shape(filters: <Filter>[_eq('a'), _eq('b')])),
        isNull,
      );
    });

    test('one field ranged and sorted needs no composite', () {
      expect(
        compositeNeed(
          _shape(
            filters: <Filter>[_range('createdAt')],
            orders: <Order>[_desc('createdAt')],
          ),
        ),
        isNull,
      );
    });

    test('equality ordered by document id ascending needs no composite', () {
      expect(
        compositeNeed(
          _shape(
            filters: <Filter>[_eq('ownerID')],
            orders: <Order>[_asc('__name__')],
          ),
        ),
        isNull,
      );
    });

    test('equality ordered by document id descending needs one', () {
      expect(
        compositeNeed(
          _shape(
            filters: <Filter>[_eq('ownerID')],
            orders: <Order>[_desc('__name__')],
          ),
        ),
        isNotNull,
      );
    });

    test('equality with a sort on another field needs one', () {
      expect(
        compositeNeed(
          _shape(
            filters: <Filter>[_eq('ownerID')],
            orders: <Order>[_desc('createdAt')],
          ),
        )?.toString(),
        'ownerID (any order), createdAt DESCENDING',
      );
    });

    test('an unsorted range field follows the sort orders', () {
      expect(
        compositeNeed(
          _shape(
            filters: <Filter>[_eq('a'), _range('c')],
            orders: <Order>[_asc('b')],
          ),
        )?.orders,
        <Order>[_asc('b'), _asc('c')],
      );
    });

    test('an unsorted range field takes the last sort\'s direction', () {
      expect(
        compositeNeed(
          _shape(
            filters: <Filter>[_eq('a'), _range('c')],
            orders: <Order>[_desc('b')],
          ),
        )?.orders,
        <Order>[_desc('b'), _desc('c')],
      );
    });

    test('a range on the document id adds no sort', () {
      expect(
        compositeNeed(
          _shape(
            filters: <Filter>[_eq('ownerID'), _range('__name__')],
            orders: <Order>[_desc('createdAt')],
          ),
        )?.toString(),
        'ownerID (any order), createdAt DESCENDING',
      );
    });

    test('a document id sort in the last sort\'s direction is implicit', () {
      expect(
        compositeNeed(
          _shape(
            filters: <Filter>[_eq('ownerID')],
            orders: <Order>[_desc('createdAt'), _desc('__name__')],
          ),
        )?.toString(),
        'ownerID (any order), createdAt DESCENDING',
      );
    });

    test('array-contains alone needs no composite, with equality it does', () {
      expect(
        compositeNeed(_shape(filters: <Filter>[_contains('tags')])),
        isNull,
      );
      expect(
        compositeNeed(_shape(filters: <Filter>[_contains('tags'), _eq('a')])),
        isNotNull,
      );
    });
  });

  group('uncoveredQueries', () {
    final QueryShape history = _shape(
      filters: <Filter>[_eq('viceID'), _eq('ownerID')],
      orders: <Order>[_desc('createdAt')],
    );

    test('equality fields match in any order', () {
      expect(
        uncoveredQueries(
          <QueryShape>[history],
          <Map<String, dynamic>>[
            _index('activities', <List<String>>[
              <String>['ownerID', 'DESCENDING'],
              <String>['viceID', 'ASCENDING'],
              <String>['createdAt', 'DESCENDING'],
            ]),
          ],
        ),
        isEmpty,
      );
    });

    // The implicit __name__ takes the direction of the last sorted field, in
    // an index and in a query alike.
    test('a trailing __name__ in the last sort\'s direction is implicit', () {
      expect(
        uncoveredQueries(
          <QueryShape>[history],
          <Map<String, dynamic>>[
            _index('activities', <List<String>>[
              <String>['viceID', 'ASCENDING'],
              <String>['ownerID', 'ASCENDING'],
              <String>['createdAt', 'DESCENDING'],
              <String>['__name__', 'DESCENDING'],
            ]),
          ],
        ),
        isEmpty,
      );
    });

    test('a trailing __name__ against the last sort is its own index', () {
      expect(
        uncoveredQueries(
          <QueryShape>[history],
          <Map<String, dynamic>>[
            _index('activities', <List<String>>[
              <String>['viceID', 'ASCENDING'],
              <String>['ownerID', 'ASCENDING'],
              <String>['createdAt', 'DESCENDING'],
              <String>['__name__', 'ASCENDING'],
            ]),
          ],
        ),
        hasLength(1),
      );
    });

    test('a query sorting __name__ against its last sort needs that index', () {
      final QueryShape paged = _shape(
        filters: <Filter>[_eq('ownerID')],
        orders: <Order>[_desc('createdAt'), _asc('__name__')],
      );
      final Map<String, dynamic> plain = _index('activities', <List<String>>[
        <String>['ownerID', 'ASCENDING'],
        <String>['createdAt', 'DESCENDING'],
      ]);
      expect(
        uncoveredQueries(<QueryShape>[paged], <Map<String, dynamic>>[plain]),
        hasLength(1),
      );
      expect(
        uncoveredQueries(
          <QueryShape>[paged],
          <Map<String, dynamic>>[
            _index('activities', <List<String>>[
              <String>['ownerID', 'ASCENDING'],
              <String>['createdAt', 'DESCENDING'],
              <String>['__name__', 'ASCENDING'],
            ]),
          ],
        ),
        isEmpty,
      );
    });

    test('a sort in the other direction is not served', () {
      expect(
        uncoveredQueries(
          <QueryShape>[history],
          <Map<String, dynamic>>[
            _index('activities', <List<String>>[
              <String>['viceID', 'ASCENDING'],
              <String>['ownerID', 'ASCENDING'],
              <String>['createdAt', 'ASCENDING'],
            ]),
          ],
        ),
        hasLength(1),
      );
    });

    test('an index on another collection or with a missing field is not', () {
      expect(
        uncoveredQueries(
          <QueryShape>[history],
          <Map<String, dynamic>>[
            _index('vices', <List<String>>[
              <String>['viceID', 'ASCENDING'],
              <String>['ownerID', 'ASCENDING'],
              <String>['createdAt', 'DESCENDING'],
            ]),
            _index('activities', <List<String>>[
              <String>['ownerID', 'ASCENDING'],
              <String>['createdAt', 'DESCENDING'],
            ]),
          ],
        ),
        hasLength(1),
      );
    });

    test('an array-contains field must be a CONTAINS entry', () {
      final QueryShape tagged = _shape(
        filters: <Filter>[_eq('ownerID'), _contains('tags')],
      );
      expect(
        uncoveredQueries(
          <QueryShape>[tagged],
          <Map<String, dynamic>>[
            _index('activities', <List<String>>[
              <String>['ownerID', 'ASCENDING'],
              <String>['tags', 'ASCENDING'],
            ]),
          ],
        ),
        hasLength(1),
      );
      expect(
        uncoveredQueries(
          <QueryShape>[tagged],
          <Map<String, dynamic>>[
            _index('activities', <List<String>>[
              <String>['ownerID', 'ASCENDING'],
              <String>['tags', 'CONTAINS'],
            ]),
          ],
        ),
        isEmpty,
      );
    });

    test('a composite query on a variable collection is reported', () {
      expect(
        uncoveredQueries(<QueryShape>[
          _shape(
            collection: null,
            filters: <Filter>[_eq('ownerID')],
            orders: <Order>[_desc('createdAt')],
          ),
        ], _indexes).single,
        contains('collection is a variable'),
      );
    });
  });

  group('scanQueries', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('index_scan'));
    tearDown(() => dir.deleteSync(recursive: true));

    QueryScan scanSource(String source) {
      File('${dir.path}/q.dart').writeAsStringSync(source);
      return scanQueries(dir);
    }

    test('reads a chain of filters and sorts', () {
      final QueryScan scan = scanSource('''
        f(db, uid) => db
            .collection('activities')
            .where('ownerID', isEqualTo: uid)
            .where('createdAt', isGreaterThanOrEqualTo: 1, isLessThan: 2)
            .orderBy('createdAt', descending: true)
            .limit(5)
            .snapshots();
        g(db) => db.collection('vices').doc('x').get();
        h(list) => list.where((x) => x > 1);
      ''');
      expect(scan.unreadable, isEmpty);
      expect(
        scan.shapes.single.toString(),
        startsWith(
          'activities (ownerID equality, createdAt inequality, '
          'createdAt inequality, orderBy createdAt desc)',
        ),
      );
    });

    test('maps FieldPath.documentId to __name__', () {
      final QueryShape shape = scanSource('''
        f(db, c) => db.collection(c).where('ownerID', isEqualTo: 1)
            .orderBy(FieldPath.documentId);
      ''').shapes.single;
      expect(shape.collection, isNull);
      expect(shape.orders, <Order>[_asc('__name__')]);
    });

    test('reports a clause outside a .collection chain', () {
      final QueryScan scan = scanSource('''
        f(db) {
          final q = db.collection('vices');
          return q.where('ownerID', isEqualTo: 1).orderBy('createdAt');
        }
      ''');
      expect(scan.unreadable, hasLength(2));
    });

    test('reports limitToLast', () {
      final QueryScan scan = scanSource('''
        f(db) => db.collection('vices')
            .where('ownerID', isEqualTo: 1)
            .orderBy('createdAt', descending: true)
            .limitToLast(5);
      ''');
      expect(scan.unreadable.single, contains('limitToLast'));
    });

    test('reports a field or direction it cannot read', () {
      final QueryScan scan = scanSource('''
        f(db, field, d) => db.collection('vices')
            .where(field, isEqualTo: 1)
            .where(Filter.or(a, b))
            .orderBy('createdAt', descending: d);
      ''');
      expect(scan.unreadable, hasLength(3));
    });
  });
}
