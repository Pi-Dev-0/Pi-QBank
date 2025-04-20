import '../../config/app_config.dart';
import 'base/nu_question_page.dart';

class NuHistoryPage extends NuQuestionPage {
  const NuHistoryPage({super.key})
      : super(
          title: 'History',
          apiUrl: AppConfig.nuHistoryApi,
        );

  @override
  NuQuestionPageState createState() => _NuHistoryPageState();
}

class _NuHistoryPageState extends NuQuestionPageState<NuHistoryPage> {}
