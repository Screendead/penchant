# Three pushNamed targets have no matching route and land on the Not Found page

**Severity:** high

Settings offers Notifications and Privacy rows that push `/settings/notifications` and `/settings/privacy`, and every row of Manage Data pushes `/vices/<id>/edit`. `onGenerateRoute` matches three- and four-segment `/vices` paths whose third segment is literally `activities`, then switches on a literal name list holding only `/manage-data`, `/vices/add`, `/settings` and `/settings/account`.

All three targets fall through to the default `NotFound` case, so three rendered and enabled affordances dead-end, including the only route for editing a vice.

## Evidence

- `lib/manage_data.dart:72` — `'/vices/${vice.id}/edit',`
- `lib/main.dart:69` — `uri.pathSegments[2] == 'activities') {`
- `lib/main.dart:105` — `default:\n                  return const NotFound();`
- `lib/settings.dart:33` — `Navigator.of(context).pushNamed('/settings/notifications');`
- `lib/settings.dart:40` — `Navigator.of(context).pushNamed('/settings/privacy');`
