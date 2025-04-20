import '../../config/app_config.dart';
import 'base/nu_question_page.dart';

class NuAccountingPage extends NuQuestionPage {
  const NuAccountingPage({super.key})
      : super(
          title: 'Accounting',
          apiUrl: AppConfig.nuAccountingApi,
        );

  @override
  NuQuestionPageState createState() => _NuAccountingPageState();
}

class _NuAccountingPageState extends NuQuestionPageState<NuAccountingPage> {}
