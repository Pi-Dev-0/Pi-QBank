import '../../config/app_config.dart';
import 'base/nu_question_page.dart';

class NuMathematicsPage extends NuQuestionPage {
  const NuMathematicsPage({super.key})
      : super(
          title: 'Mathematics',
          apiUrl: AppConfig.nuMathematicsApi,
        );

  @override
  NuQuestionPageState createState() => _NuMathematicsPageState();
}

class _NuMathematicsPageState extends NuQuestionPageState<NuMathematicsPage> {}
