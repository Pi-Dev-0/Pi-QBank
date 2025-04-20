import '../../config/app_config.dart';
import 'base/nu_question_page.dart';

class NuBanglaPage extends NuQuestionPage {
  const NuBanglaPage({super.key})
      : super(
          title: 'Bangla',
          apiUrl: AppConfig.nuBanglaApi,
        );

  @override
  NuQuestionPageState createState() => _NuBanglaPageState();
}

class _NuBanglaPageState extends NuQuestionPageState<NuBanglaPage> {}
