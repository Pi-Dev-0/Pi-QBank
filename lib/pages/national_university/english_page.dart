import '../../config/app_config.dart';
import 'base/nu_question_page.dart';

class NuEnglishPage extends NuQuestionPage {
  const NuEnglishPage({super.key})
      : super(
          title: 'English',
          apiUrl: AppConfig.nuEnglishApi,
        );

  @override
  NuQuestionPageState createState() => _NuEnglishPageState();
}

class _NuEnglishPageState extends NuQuestionPageState<NuEnglishPage> {}
