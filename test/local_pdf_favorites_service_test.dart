import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/services/local_pdf_favorites_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists and reloads favorite local PDF paths', () async {
    SharedPreferences.setMockInitialValues({});

    await LocalPdfFavoritesService.saveFavorites({
      '/storage/emulated/0/Download/algebra.pdf',
      '/storage/emulated/0/Download/physics.pdf',
    });

    final favorites = await LocalPdfFavoritesService.getFavorites();

    expect(
      favorites,
      {
        '/storage/emulated/0/Download/algebra.pdf',
        '/storage/emulated/0/Download/physics.pdf',
      },
    );
  });
}
