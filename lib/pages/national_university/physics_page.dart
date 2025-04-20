import '../../config/app_config.dart';
import 'base/nu_question_page.dart';

class NuPhysicsPage extends NuQuestionPage {
  const NuPhysicsPage({super.key})
      : super(
          title: 'Physics',
          apiUrl: AppConfig.nuPhysicsApi,
        );

  @override
  NuQuestionPageState createState() => _NuPhysicsPageState();
}

class _NuPhysicsPageState extends NuQuestionPageState<NuPhysicsPage> {}
