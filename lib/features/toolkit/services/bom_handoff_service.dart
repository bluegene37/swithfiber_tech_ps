import 'package:signals_flutter/signals_flutter.dart';

/// Calculated Bill of Materials staged from Toolkit's Drop Cable Estimator for
/// 1-tap import into a Job Completion Report or Repair Detail screen.
class StagedBom {
  final Map<String, int> materials;
  final String summary;
  final DateTime stagedAt;

  const StagedBom({
    required this.materials,
    required this.summary,
    required this.stagedAt,
  });
}

// Gene - Nov, 23, 2026: Shared reactive handoff bridge from Drop Cable Estimator BOM to Job & Repair reports.
class BomHandoffService {
  BomHandoffService._();
  static final BomHandoffService instance = BomHandoffService._();

  final pendingBom = signal<StagedBom?>(null);

  void stageBom(Map<String, int> materials, {String summary = ''}) {
    final cleaned = <String, int>{
      for (final entry in materials.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    if (cleaned.isEmpty) return;
    pendingBom.value = StagedBom(
      materials: Map.unmodifiable(cleaned),
      summary: summary,
      stagedAt: DateTime.now(),
    );
  }

  void clear() {
    pendingBom.value = null;
  }
}
