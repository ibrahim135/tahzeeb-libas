enum MeasurementConfiguration { upper, lower, both, none }

enum GarmentType {
  sherwani('Sherwani', MeasurementConfiguration.both, {
    'sherwani': 'Sherwani',
    'three_piece': '3-piece',
  }),
  suit('Suit', MeasurementConfiguration.both, {
    'two_piece': '2-piece',
    'three_piece': '3-piece',
    'four_piece': '4-piece',
  }),
  jothpuri('Jothpuri', MeasurementConfiguration.both),
  sadri('Sadri', MeasurementConfiguration.upper),
  pant('Pant', MeasurementConfiguration.lower),
  shirt('Shirt', MeasurementConfiguration.upper),
  kurta('Kurta', MeasurementConfiguration.upper),
  payjama('Payjama', MeasurementConfiguration.lower),
  thobe('Thobe', MeasurementConfiguration.upper),
  joota('Joota', MeasurementConfiguration.none),
  pagdi('Pagdi', MeasurementConfiguration.none);

  final String label;
  final MeasurementConfiguration defaultConfiguration;
  final Map<String, String> variants;
  const GarmentType(
    this.label,
    this.defaultConfiguration, [
    this.variants = const {},
  ]);
  void validateVariant(String? variant) {
    if (variants.isEmpty ? variant != null : !variants.containsKey(variant)) {
      throw ArgumentError('Select a valid garment variant.');
    }
  }
}

const upperFields = {
  'upper_length',
  'upper_shoulder',
  'upper_sleeves',
  'upper_arms',
  'upper_cuffs',
  'upper_chest',
  'upper_stomach',
  'upper_hips',
  'upper_neck',
};
const lowerFields = {
  'lower_length',
  'lower_waist',
  'lower_hips',
  'lower_thighs',
  'lower_knees',
  'lower_bottom',
  'lower_allround',
  'lower_inside',
};

final class MeasurementSnapshot {
  final MeasurementConfiguration configuration;
  final Map<String, String> values;
  MeasurementSnapshot(this.configuration, Map<String, String> input)
    : values = Map.unmodifiable(
        input.map((key, value) => MapEntry(key, _decimal(value))),
      ) {
    final allowed = switch (configuration) {
      MeasurementConfiguration.upper => upperFields,
      MeasurementConfiguration.lower => lowerFields,
      MeasurementConfiguration.both => {...upperFields, ...lowerFields},
      MeasurementConfiguration.none => <String>{},
    };
    if (values.keys.any((key) => !allowed.contains(key))) {
      throw ArgumentError('Measurement does not belong to an enabled section.');
    }
  }
  static String _decimal(String text) {
    if (!RegExp(r'^\d{1,3}(\.\d{1,3})?$').hasMatch(text)) {
      throw const FormatException(
        'Enter inches with up to three decimal places.',
      );
    }
    final parts = text.split('.');
    final fraction = parts.length > 1
        ? parts[1].replaceFirst(RegExp(r'0+$'), '')
        : '';
    final whole = int.parse(parts[0]);
    if (whole == 0 && fraction.isEmpty) {
      throw const FormatException('Measurements must be positive.');
    }
    return fraction.isEmpty ? '$whole' : '$whole.$fraction';
  }
}
