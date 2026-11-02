# The history ListTile's onTap and its trailing Edit button push the same route

**Severity:** low

Each row pushes the same activity-editor path from its `onTap` and again from a trailing edit `IconButton`, with byte-identical handlers.

The pencil icon therefore adds no capability the row tap does not already provide, while occupying trailing space directly beside the destructive delete icon in the row's smallest touch region.

## Evidence

- `lib/vice_activity_history_page.dart:63` — `onTap: () {\n                      Navigator.of(context).pushNamed(\n                        '/vices/$viceID/activities/${activity.id}',\n                      );\n                    },`
- `lib/vice_activity_history_page.dart:74` — `onPressed: () {\n                            Navigator.of(context).pushNamed(\n                              '/vices/$viceID/activities/${activity.id}',\n                            );\n                          },`
