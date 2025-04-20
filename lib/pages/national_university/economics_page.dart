import '../../config/app_config.dart';
import 'base/nu_question_page.dart';

class NuEconomicsPage extends NuQuestionPage {
  const NuEconomicsPage({super.key})
      : super(
          title: 'Economics',
          apiUrl: AppConfig.nuEconomicsApi,
        );

  @override
  NuQuestionPageState createState() => _NuEconomicsPageState();
}

class _NuEconomicsPageState extends NuQuestionPageState<NuEconomicsPage> {}
