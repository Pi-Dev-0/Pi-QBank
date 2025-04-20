import '../../config/app_config.dart';
import 'base/nu_question_page.dart';

class NuStatisticsPage extends NuQuestionPage {
  const NuStatisticsPage({super.key})
      : super(
          title: 'Statistics',
          apiUrl: AppConfig.nuStatisticsApi,
        );

  @override
  NuQuestionPageState createState() => _NuStatisticsPageState();
}

class _NuStatisticsPageState extends NuQuestionPageState<NuStatisticsPage> {}
