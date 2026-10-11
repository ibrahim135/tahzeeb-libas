final class ShopSettingsRecord {
  final String name;
  final String? address, contact, receiptNotes;
  final DateTime updatedAt;
  ShopSettingsRecord({
    required this.name,
    this.address,
    this.contact,
    this.receiptNotes,
    required this.updatedAt,
  }) {
    if (name.trim().isEmpty) throw ArgumentError('Enter the shop name.');
    if (!updatedAt.isUtc) throw ArgumentError('Use a UTC settings timestamp.');
  }
}
