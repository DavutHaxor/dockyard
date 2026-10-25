import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppSection { overview, containers, metrics, settings }

final selectedSectionProvider = StateProvider<AppSection>(
  (ref) => AppSection.overview,
);
