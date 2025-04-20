import '../../config/app_config.dart';
import 'base/nu_question_page.dart';

class NuIslamicStudiesPage extends NuQuestionPage {
  const NuIslamicStudiesPage({super.key})
      : super(
          title: 'Islamic Studies',
          apiUrl: AppConfig.nuIslamicStudiesApi,
        );

  @override
  NuQuestionPageState createState() => _NuIslamicStudiesPageState();
}

class _NuIslamicStudiesPageState
    extends NuQuestionPageState<NuIslamicStudiesPage> {}
