# The usage graph sizes its date labels from one sample date

**Severity:** low

The bottom axis decides how many date labels fit by measuring one formatted date, 30 May. In a region whose short form of another month is wider (en_GB writes "Sept"), labels can come out wider than measured and crowd. The overlap tests run only in the test locale, so they do not catch it.

## Evidence

- `lib/usage_graph_view.dart:388` — `formatShortDay(DateTime(2000, 5, 30)),`
