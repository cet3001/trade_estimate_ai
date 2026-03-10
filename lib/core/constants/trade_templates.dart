import 'package:flutter/material.dart';
import 'app_colors.dart';

enum TradeType {
  plumbing,
  electrical,
  roofing,
  construction,
}

extension TradeTypeExtension on TradeType {
  String get displayName {
    switch (this) {
      case TradeType.plumbing:
        return 'Plumbing';
      case TradeType.electrical:
        return 'Electrical';
      case TradeType.roofing:
        return 'Roofing';
      case TradeType.construction:
        return 'Construction';
    }
  }

  String get emoji {
    switch (this) {
      case TradeType.plumbing:
        return '🔧';
      case TradeType.electrical:
        return '⚡';
      case TradeType.roofing:
        return '🏠';
      case TradeType.construction:
        return '🏗';
    }
  }

  Color get color {
    switch (this) {
      case TradeType.plumbing:
        return AppColors.plumbing;
      case TradeType.electrical:
        return AppColors.electrical;
      case TradeType.roofing:
        return AppColors.roofing;
      case TradeType.construction:
        return AppColors.construction;
    }
  }

  String get value {
    return name;
  }

  static TradeType fromString(String value) {
    return TradeType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => TradeType.plumbing,
    );
  }
}

/// Display metadata for a single trade.
class TradeInfo {
  final TradeType type;
  final String label;
  final String emoji;
  final Color color;

  /// String key for the trade (e.g. 'plumbing'), matching [TradeType.value].
  String get key => type.value;

  const TradeInfo({
    required this.type,
    required this.label,
    required this.emoji,
    required this.color,
  });
}

class TradeTemplates {
  static const Map<TradeType, String> systemPrompts = {
    TradeType.plumbing:
        'You are writing a professional plumbing estimate for a licensed plumber. '
        'Use industry-standard plumbing terminology. Reference pipe types, fixture brands, '
        'and code compliance where appropriate. Mention cleanup and site protection.',
    TradeType.electrical:
        'You are writing a professional electrical estimate for a licensed electrician. '
        'Reference NEC code compliance, permit requirements, and safety standards. '
        'Use electrical terminology (panels, circuits, breakers, conduit, gauge).',
    TradeType.roofing:
        'You are writing a professional roofing estimate for a licensed roofing contractor. '
        'Reference material quality, manufacturer warranties, underlayment, flashing, '
        'and proper disposal of old materials.',
    TradeType.construction:
        'You are writing a professional construction estimate for a general contractor. '
        'Reference building code compliance, subcontractor coordination, site safety, '
        'material sourcing, and project milestones.',
  };

  static const Map<TradeType, List<String>> workTypes = {
    TradeType.plumbing: ['Repair', 'New Install', 'Replacement', 'Inspection'],
    TradeType.electrical: [
      'Panel Upgrade',
      'New Circuits',
      'Repair',
      'EV Charger',
      'Whole Home Rewire'
    ],
    TradeType.roofing: [
      'Full Replacement',
      'Repair',
      'Inspection',
      'Gutters',
      'Flashing'
    ],
    TradeType.construction: [
      'Addition',
      'Remodel',
      'New Build',
      'Demo',
      'Framing',
      'Drywall',
      'Other'
    ],
  };

  /// Ordered list of all trade display metadata.
  static const List<TradeInfo> all = [
    TradeInfo(
      type: TradeType.plumbing,
      label: 'Plumbing',
      emoji: '🔧',
      color: AppColors.plumbing,
    ),
    TradeInfo(
      type: TradeType.electrical,
      label: 'Electrical',
      emoji: '⚡',
      color: AppColors.electrical,
    ),
    TradeInfo(
      type: TradeType.roofing,
      label: 'Roofing',
      emoji: '🏠',
      color: AppColors.roofing,
    ),
    TradeInfo(
      type: TradeType.construction,
      label: 'Construction',
      emoji: '🏗',
      color: AppColors.construction,
    ),
  ];

  static TradeInfo byType(TradeType type) =>
      all.firstWhere((t) => t.type == type);
}
