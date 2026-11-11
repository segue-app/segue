import 'package:flutter/widgets.dart';

/// Name of the route on top of [nav], without changing anything.
String? topRouteName(NavigatorState nav) {
  String? name;
  nav.popUntil((route) {
    name = route.settings.name;
    return true; // stop at the top route: nothing is popped
  });
  return name;
}

/// Pushes [route] unless the same page (same route name) is already on top,
/// so tapping a menu item twice doesn't stack duplicate pages.
void pushUnique(NavigatorState? nav, Route<void> route) {
  if (nav == null) return;
  final name = route.settings.name;
  if (name != null && topRouteName(nav) == name) return;
  nav.push(route);
}
