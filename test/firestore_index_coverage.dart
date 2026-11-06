import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

// The index rules modelled here follow
// https://firebase.google.com/docs/firestore/query-data/index-overview:
// automatic single-field indexes serve a query on one field, merged
// single-field indexes serve equality-only queries, and anything else needs a
// composite index whose fields are the equality fields, then the sort orders,
// then range fields not already sorted on. Every index ends with an implicit
// __name__ in the direction of its last sorted field (ascending when none),
// and every query with an implicit __name__ sort in the direction of its last
// orderBy, which also orders its unsorted range fields: the client SDK sends
// these normalized sorts (queryNormalizedOrderBy in @firebase/firestore).
// Where Firestore might combine several composites, this asks for one, so it
// can demand an index Firestore would not, never the reverse.

enum FilterKind { equality, contains, inequality }

typedef Filter = ({String field, FilterKind kind});
typedef Order = ({String field, bool descending});

class QueryShape {
  QueryShape({
    required this.collection,
    required this.location,
    this.filters = const <Filter>[],
    this.orders = const <Order>[],
  });

  // Null when the code names the collection with a variable.
  final String? collection;
  final String location;
  final List<Filter> filters;
  final List<Order> orders;

  @override
  String toString() {
    final String clauses = <String>[
      for (final Filter f in filters) '${f.field} ${f.kind.name}',
      for (final Order o in orders)
        'orderBy ${o.field}${o.descending ? ' desc' : ''}',
    ].join(', ');
    return '${collection ?? '<variable>'} ($clauses) at $location';
  }
}

// A composite index a shape needs: [prefix] in any order, then [orders] in
// sequence.
class CompositeNeed {
  CompositeNeed({
    required this.equality,
    required this.contains,
    required this.orders,
  });

  final Set<String> equality;
  final Set<String> contains;
  final List<Order> orders;

  @override
  String toString() => <String>[
    for (final String f in equality) '$f (any order)',
    for (final String f in contains) '$f CONTAINS',
    for (final Order o in orders)
      '${o.field} ${o.descending ? 'DESCENDING' : 'ASCENDING'}',
  ].join(', ');
}

// Drops a trailing __name__ whose direction is the implicit one: that of the
// sort before it, or ascending when nothing precedes it.
void _dropImplicitTail(List<Order> orders) {
  while (orders.isNotEmpty && orders.last.field == '__name__') {
    final bool implicitDescending =
        orders.length > 1 && orders[orders.length - 2].descending;
    if (orders.last.descending != implicitDescending) return;
    orders.removeLast();
  }
}

// Null when automatic single-field indexes serve the shape.
CompositeNeed? compositeNeed(QueryShape shape) {
  final Set<String> equality = <String>{
    for (final Filter f in shape.filters)
      if (f.kind == FilterKind.equality) f.field,
  };
  final Set<String> contains = <String>{
    for (final Filter f in shape.filters)
      if (f.kind == FilterKind.contains) f.field,
  };
  final Set<String> ordered = <String>{
    for (final Order o in shape.orders) o.field,
  };
  final List<String> unsortedRanges = <String>{
    for (final Filter f in shape.filters)
      if (f.kind == FilterKind.inequality &&
          f.field != '__name__' &&
          !ordered.contains(f.field))
        f.field,
  }.toList()..sort();
  final bool lastDescending =
      shape.orders.isNotEmpty && shape.orders.last.descending;
  final List<Order> orders = <Order>[
    ...shape.orders,
    for (final String field in unsortedRanges)
      (field: field, descending: lastDescending),
  ];
  _dropImplicitTail(orders);

  final bool singleField = contains.isEmpty
      ? orders.isEmpty || (equality.isEmpty && orders.length == 1)
      : equality.isEmpty && orders.isEmpty && contains.length == 1;
  if (singleField) return null;
  return CompositeNeed(equality: equality, contains: contains, orders: orders);
}

bool serves(Map<String, dynamic> index, String collection, CompositeNeed need) {
  if (index['collectionGroup'] != collection ||
      (index['queryScope'] ?? 'COLLECTION') != 'COLLECTION') {
    return false;
  }
  final List<Map<String, dynamic>> fields = (index['fields'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .toList();
  while (fields.isNotEmpty && fields.last['fieldPath'] == '__name__') {
    String implicit = 'ASCENDING';
    for (final Map<String, dynamic> f in fields.take(fields.length - 1)) {
      implicit = f['order'] as String? ?? implicit;
    }
    if (fields.last['order'] != implicit) break;
    fields.removeLast();
  }
  final int prefixLength = need.equality.length + need.contains.length;
  if (fields.length != prefixLength + need.orders.length) return false;

  final Set<String> seenEquality = <String>{};
  final Set<String> seenContains = <String>{};
  for (final Map<String, dynamic> field in fields.take(prefixLength)) {
    final String path = field['fieldPath'] as String;
    if (field['arrayConfig'] == 'CONTAINS') {
      seenContains.add(path);
    } else if (field['order'] != null) {
      seenEquality.add(path);
    }
  }
  if (seenEquality.length != need.equality.length ||
      !seenEquality.containsAll(need.equality) ||
      seenContains.length != need.contains.length ||
      !seenContains.containsAll(need.contains)) {
    return false;
  }

  for (int i = 0; i < need.orders.length; i++) {
    final Map<String, dynamic> field = fields[prefixLength + i];
    final Order order = need.orders[i];
    if (field['fieldPath'] != order.field ||
        field['order'] != (order.descending ? 'DESCENDING' : 'ASCENDING')) {
      return false;
    }
  }
  return true;
}

// Each problem is one line naming the query's source location.
List<String> uncoveredQueries(
  List<QueryShape> shapes,
  List<Map<String, dynamic>> indexes,
) {
  final List<String> problems = <String>[];
  for (final QueryShape shape in shapes) {
    final CompositeNeed? need = compositeNeed(shape);
    if (need == null) continue;
    final String? collection = shape.collection;
    if (collection == null) {
      problems.add(
        '$shape needs a composite index ($need), but its collection is a '
        'variable; name the collection in the query',
      );
    } else if (!indexes.any(
      (Map<String, dynamic> index) => serves(index, collection, need),
    )) {
      problems.add(
        '$shape needs a composite index ($need) that firestore.indexes.json '
        'lacks',
      );
    }
  }
  return problems;
}

const Set<String> _equalityArgs = <String>{'isEqualTo', 'whereIn'};
const Set<String> _containsArgs = <String>{'arrayContains', 'arrayContainsAny'};
const Set<String> _inequalityArgs = <String>{
  'isNotEqualTo',
  'isLessThan',
  'isLessThanOrEqualTo',
  'isGreaterThan',
  'isGreaterThanOrEqualTo',
  'whereNotIn',
};
const Set<String> _filterArgs = <String>{
  ..._equalityArgs,
  ..._containsArgs,
  ..._inequalityArgs,
  'isNull',
};

class QueryScan {
  final List<QueryShape> shapes = <QueryShape>[];
  // Query clauses this scan could not read; each fails the check.
  final List<String> unreadable = <String>[];
}

// Reads every query built in one chain from `.collection(...)` in the Dart
// files under [directory]. A Firestore-shaped where or orderBy anywhere else
// is reported as unreadable, so a query assembled on a variable cannot slip
// past the check.
QueryScan scanQueries(Directory directory) {
  final QueryScan scan = QueryScan();
  final List<File> files =
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  for (final File file in files) {
    final ParseStringResult parsed = parseString(
      content: file.readAsStringSync(),
      path: file.path,
    );
    final _QueryVisitor visitor = _QueryVisitor(
      scan,
      (AstNode node) =>
          '${file.path}:${parsed.lineInfo.getLocation(node.offset).lineNumber}',
    );
    parsed.unit.accept(visitor);
    visitor.reportStrays();
  }
  return scan;
}

class _QueryVisitor extends RecursiveAstVisitor<void> {
  _QueryVisitor(this.scan, this.locate);

  final QueryScan scan;
  final String Function(AstNode) locate;
  final Set<MethodInvocation> _read = <MethodInvocation>{};
  final List<MethodInvocation> _clauses = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final String name = node.methodName.name;
    if (name == 'orderBy' || (name == 'where' && _hasFilterArg(node))) {
      _clauses.add(node);
    }
    if (name == 'collection' && node.argumentList.arguments.length == 1) {
      _readChain(node);
    }
    super.visitMethodInvocation(node);
  }

  void reportStrays() {
    for (final MethodInvocation clause in _clauses) {
      if (!_read.contains(clause)) {
        scan.unreadable.add(
          '${locate(clause)}: ${clause.methodName.name} is not in a chain '
          'from .collection(...)',
        );
      }
    }
  }

  static bool _hasFilterArg(MethodInvocation node) =>
      node.argumentList.arguments.any(
        (Expression arg) =>
            (arg is NamedExpression &&
                _filterArgs.contains(arg.name.label.name)) ||
            arg.toSource().startsWith('Filter'),
      );

  void _readChain(MethodInvocation collectionCall) {
    final Expression arg = collectionCall.argumentList.arguments.single;
    final List<Filter> filters = <Filter>[];
    final List<Order> orders = <Order>[];
    AstNode link = collectionCall;
    while (true) {
      final AstNode? next = link.parent;
      if (next is! MethodInvocation || next.target != link) break;
      final String name = next.methodName.name;
      if (name == 'doc') return;
      if (name == 'limitToLast') {
        // The SDK reverses every sort before sending, so the index it needs
        // is not the one the chain spells.
        scan.unreadable.add(
          '${locate(next)}: limitToLast, whose reversed sorts this check '
          'does not model',
        );
      }
      if (name == 'where') {
        _read.add(next);
        filters.addAll(_readWhere(next));
      } else if (name == 'orderBy') {
        _read.add(next);
        orders.add(_readOrderBy(next));
      }
      link = next;
    }
    scan.shapes.add(
      QueryShape(
        collection: arg is SimpleStringLiteral ? arg.value : null,
        location: locate(collectionCall),
        filters: filters,
        orders: orders,
      ),
    );
  }

  // Null, reported, when the field is not a literal or the document id.
  String? _field(MethodInvocation call) {
    final Expression first = call.argumentList.arguments.first;
    if (first is SimpleStringLiteral) return first.value;
    if (first is PrefixedIdentifier &&
        first.prefix.name == 'FieldPath' &&
        first.identifier.name == 'documentId') {
      return '__name__';
    }
    scan.unreadable.add(
      '${locate(call)}: ${call.methodName.name} on a field this check '
      'cannot read: ${first.toSource()}',
    );
    return null;
  }

  List<Filter> _readWhere(MethodInvocation call) {
    final String? field = _field(call);
    if (field == null) return const <Filter>[];
    final List<Filter> filters = <Filter>[];
    for (final Expression arg in call.argumentList.arguments.skip(1)) {
      if (arg is! NamedExpression) continue;
      final String name = arg.name.label.name;
      final Expression value = arg.expression;
      final FilterKind? kind = _equalityArgs.contains(name)
          ? FilterKind.equality
          : _containsArgs.contains(name)
          ? FilterKind.contains
          : _inequalityArgs.contains(name)
          ? FilterKind.inequality
          : name == 'isNull' && value is BooleanLiteral
          ? (value.value ? FilterKind.equality : FilterKind.inequality)
          : null;
      if (kind == null) {
        scan.unreadable.add(
          '${locate(call)}: where argument this check cannot read: '
          '${arg.toSource()}',
        );
      } else {
        filters.add((field: field, kind: kind));
      }
    }
    if (filters.isEmpty) {
      scan.unreadable.add('${locate(call)}: where with no filter it can read');
    }
    return filters;
  }

  Order _readOrderBy(MethodInvocation call) {
    final String field =
        _field(call) ?? call.argumentList.arguments.first.toSource();
    bool descending = false;
    for (final Expression arg in call.argumentList.arguments.skip(1)) {
      if (arg is NamedExpression && arg.name.label.name == 'descending') {
        if (arg.expression case BooleanLiteral(:final bool value)) {
          descending = value;
        } else {
          scan.unreadable.add(
            '${locate(call)}: orderBy direction this check cannot read: '
            '${arg.expression.toSource()}',
          );
        }
      }
    }
    return (field: field, descending: descending);
  }
}
