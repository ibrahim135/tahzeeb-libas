/// Exact amounts bounded well below SQLite's signed 64-bit limit.
final class Money {
  static const maxPaise = 100000000000; // ₹1 billion per order.
  final int paise;
  Money(this.paise) {
    if (paise < 0 || paise > maxPaise) {
      throw ArgumentError('Amount is outside the supported range.');
    }
  }
  factory Money.parse(String input) {
    final text = input.trim();
    if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(text)) {
      throw const FormatException(
        'Enter a positive amount with up to two decimals.',
      );
    }
    final parts = text.split('.');
    return Money(
      int.parse(parts[0]) * 100 +
          (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'))),
    );
  }
  String get decimal =>
      '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';
}

/// A business date without a timezone, represented canonically in SQLite/XLSX.
final class BusinessDate implements Comparable<BusinessDate> {
  final String iso;
  BusinessDate._(this.iso);
  factory BusinessDate.parse(String text) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      throw const FormatException('Expected YYYY-MM-DD.');
    }
    final parts = text.split('-').map(int.parse).toList();
    final date = DateTime.utc(parts[0], parts[1], parts[2]);
    if (parts[0] < 1900 ||
        date.year != parts[0] ||
        date.month != parts[1] ||
        date.day != parts[2]) {
      throw const FormatException('Invalid calendar date.');
    }
    return BusinessDate._(text);
  }
  factory BusinessDate.today() {
    final now = DateTime.now();
    return BusinessDate.parse(
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    );
  }
  String get display =>
      '${iso.substring(8)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';
  @override
  int compareTo(BusinessDate other) => iso.compareTo(other.iso);
}

String requireId(String value) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value)) {
    throw ArgumentError('A valid UUID is required.');
  }
  return value;
}

String normalizeName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
String? phoneSearch(String? value) {
  if (value == null) return null;
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : digits;
}

String billKey(String value) {
  if (value.trim().isEmpty || value.trim().length > 64) {
    throw ArgumentError('Bill number must contain 1–64 characters.');
  }
  return value.trim().toLowerCase();
}
