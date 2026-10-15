import 'package:flutter/widgets.dart' show StringCharacters;

/// Texto em minúsculas e sem acentos, para pesquisas e comparações.
String foldText(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const to = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i == -1 ? ch : to[i]);
  }
  return b.toString().toLowerCase();
}

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Primeira letra (ou algarismo) de um nome, em maiúscula, para avatares sem
/// fotografia. Ignora símbolos e emojis no início ("@joão" → "J", "🎉 Ana" → "A").
String initialOf(String name) {
  for (final ch in name.characters) {
    if (_letterOrDigit.hasMatch(ch)) return ch.toUpperCase();
  }
  return '?';
}
