import '../../config/app_config.dart';
import 'base/nu_question_page.dart';

class NuChemistryPage extends NuQuestionPage {
  const NuChemistryPage({super.key})
      : super(
          title: 'Chemistry',
          apiUrl: AppConfig.nuChemistryApi,
        );

  @override
  NuQuestionPageState createState() => _NuChemistryPageState();
}

class _NuChemistryPageState extends NuQuestionPageState<NuChemistryPage> {}
