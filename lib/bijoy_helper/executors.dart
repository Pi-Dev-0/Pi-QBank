part of 'bijoy_helper.dart';


String _toBijoy(String unicodeStr) {
  return Unicode().convertUnicodeToBijoy(unicodeStr);
}

String _toUnicode(String bijoyStr) {
  return Unicode().convertBijoyToUnicode(bijoyStr);
}