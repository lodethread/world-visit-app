import 'package:unorm_dart/unorm_dart.dart' as unorm;

final _combiningMarks = RegExp(r'[\p{Mn}\p{Me}\p{Mc}]', unicode: true);
final _nonWord = RegExp(r'[^\p{Letter}\p{Number}]+', unicode: true);
final _multiSpace = RegExp(r'\s+');

String normalizeText(String input) {
  var value = input.trim();
  if (value.isEmpty) {
    return '';
  }
  value = unorm.nfkd(value);
  value = value.toLowerCase();
  value = value.replaceAll(_combiningMarks, '');
  value = value.replaceAll(_nonWord, ' ');
  value = value.replaceAll(_multiSpace, ' ').trim();
  return value;
}
