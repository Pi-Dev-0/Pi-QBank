import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'pages/home_page.dart';
import 'pages/online_class_page.dart';
import 'pages/ai_page.dart';
import 'pages/seven_college/sevec_college_mathematics.dart';
import 'pages/info_page.dart';
import 'pages/class_pages.dart';
import 'pages/national_university_page.dart';
import 'pages/seven_college_page.dart';
import 'pages/nursing_admission_page.dart';
import 'pages/nursing_page.dart';
import 'pages/books_page.dart';
import 'pages/class1/bangla_page.dart';
import 'pages/class1/english_page.dart';
import 'pages/class1/math_page.dart';
import 'pages/class3/science_page.dart';
import 'pages/class3/social_science_page.dart';
import 'pages/class3/religion_page.dart';
import 'pages/class4/science_page.dart';
import 'pages/class4/social_science_page.dart';
import 'pages/class4/religion_page.dart';
import 'pages/class5/science_page.dart';
import 'pages/class5/social_science_page.dart';
import 'pages/class5/religion_page.dart';
import 'pages/class2/bangla_page.dart';
import 'pages/class2/english_page.dart';
import 'pages/class2/math_page.dart';
import 'pages/class3/bangla_page.dart';
import 'pages/class3/english_page.dart';
import 'pages/class3/math_page.dart';
import 'pages/class4/bangla_page.dart';
import 'pages/class4/english_page.dart';
import 'pages/class4/math_page.dart';
import 'pages/class5/bangla_page.dart';
import 'pages/class5/english_page.dart';
import 'pages/class5/math_page.dart';
import 'pages/class6/math_page.dart';
import 'pages/class6/bangla_page.dart';
import 'pages/class6/english_page.dart';
import 'pages/ssc_page.dart';
import 'pages/hsc_page.dart';
import 'pages/universities_page.dart';
import 'pages/engineering_universities_page.dart';
import 'pages/gst_page.dart';
import 'pages/medical_page.dart';
import 'pages/seven_college_admission_page.dart';
import 'pages/bookmarks_page.dart';
import 'pages/downloaded_papers_page.dart';
import 'pages/file_upload_page.dart';
import 'pages/ssc/bangla_first_paper.dart';
import 'pages/ssc/bangla_second_paper.dart';
import 'pages/ssc/english_first_paper.dart';
import 'pages/ssc/english_second_paper.dart';
import 'pages/ssc/mathematics.dart';
import 'pages/ssc/history.dart';
import 'pages/ssc/higher_math.dart';
import 'pages/ssc/physics.dart';
import 'pages/ssc/chemistry.dart';
import 'pages/ssc/biology.dart';
import 'pages/ssc/bangla_literature.dart';
import 'pages/ssc/bangladesh_global_studies.dart';
import 'pages/ssc/ict.dart';
import 'pages/ssc/religion.dart';
import 'pages/ssc/civics.dart';
import 'pages/ssc/geography.dart';
import 'pages/hsc/bangla_first_paper.dart';
import 'pages/hsc/bangla_second_paper.dart';
import 'pages/hsc/english_first_paper.dart';
import 'pages/hsc/english_second_paper.dart';
import 'pages/hsc/physics_first_paper.dart';
import 'pages/hsc/physics_second_paper.dart';
import 'pages/hsc/chemistry_first_paper.dart';
import 'pages/hsc/chemistry_second_paper.dart';
import 'pages/hsc/biology_first_paper.dart';
import 'pages/hsc/biology_second_paper.dart';
import 'pages/hsc/higher_math_first_paper.dart';
import 'pages/hsc/higher_math_second_paper.dart';
import 'pages/hsc/history_first_paper.dart';
import 'pages/hsc/history_second_paper.dart';
import 'pages/hsc/geography_first_paper.dart';
import 'pages/hsc/geography_second_paper.dart';
import 'pages/hsc/economics_first_paper.dart';
import 'pages/hsc/economics_second_paper.dart';
import 'pages/hsc/accounting_first_paper.dart';
import 'pages/hsc/accounting_second_paper.dart';
import 'pages/hsc/business_org_first_paper.dart';
import 'pages/hsc/business_org_second_paper.dart';
import 'pages/hsc/production_management.dart';
import 'pages/hsc/ict.dart';
import 'package:provider/provider.dart';
import 'services/connectivity_service.dart';
import 'providers/app_mode_provider.dart';
import 'widgets/connectivity_wrapper.dart';
import 'pages/ssc/accounting.dart';
import 'pages/ssc/finance.dart';
import 'pages/ssc/business.dart';
import 'pages/ssc/economics.dart';
import 'pages/formula_page.dart';
import 'pages/suggestions_page.dart';
import 'pages/class7/bangla_page.dart';
import 'pages/class7/english_page.dart';
import 'pages/class7/math_page.dart';
import 'pages/class7/science_page.dart';
import 'pages/class7/social_science_page.dart';
import 'pages/class7/islamic_studies_page.dart';
import 'pages/class8/bangla_page.dart';
import 'pages/class8/english_page.dart';
import 'pages/class8/math_page.dart';
import 'pages/class8/science_page.dart';
import 'pages/class8/social_science_page.dart';
import 'pages/class8/islamic_studies_page.dart';
import 'pages/class6/arts_culture_page.dart';
import 'pages/class6/islamic_studies_page.dart';
import 'pages/class6/science_page.dart';
import 'pages/university_admission/dhaka_university.dart';
import 'pages/university_admission/rajshahi_university.dart';
import 'pages/university_admission/chittagong_university.dart';
import 'pages/university_admission/jahangirnagar_university.dart';
import 'pages/engineering_university_admission/buet_page.dart';
import 'pages/engineering_university_admission/cuet_page.dart';
import 'pages/engineering_university_admission/ruet_page.dart';
import 'pages/engineering_university_admission/kuet_page.dart';
import 'pages/engineering_university_admission/duet_page.dart';
import 'pages/national_university/mathematics_page.dart';
import 'pages/national_university/physics_page.dart';
import 'pages/national_university/chemistry_page.dart';
import 'pages/national_university/statistics_page.dart';
import 'pages/national_university/economics_page.dart';
import 'pages/national_university/accounting_page.dart';
import 'pages/national_university/management_page.dart';
import 'pages/national_university/english_page.dart';
import 'pages/national_university/bangla_page.dart';
import 'pages/national_university/history_page.dart';
import 'pages/national_university/islamic_studies_page.dart';
import 'pages/pdf_reader_page.dart';
import 'pages/tools_page.dart';
import 'pages/blog_page.dart';
import 'widgets/custom_bottom_navigation_bar.dart';
import 'pages/feedback_page.dart';
import 'pages/question_bank_content.dart';
import 'pages/guide_book.dart';
import 'pages/notes_remainder_page.dart';
import 'pages/hand_notes/hand_notes_page.dart';
import 'services/adsterra_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityService()),
        ChangeNotifierProvider(create: (_) => AppModeProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pi-Mathematics',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        fontFamily: 'HindSiliguri',
      ),
      home: const MainScreen(),
      builder: (context, child) {
        return Stack(
          children: [
            ConnectivityWrapper(
              child: child ?? const SizedBox(),
            ),
            // Global Hidden Ad Trigger
            AdsterraService.showAd(),
          ],
        );
      },
      routes: {
        '/question_bank_content': (context) => const QuestionBankContent(),
        '/guide_book': (context) => const GuideBookPage(),
        '/notes_remainder': (context) => const NotesRemainderPage(),
        '/feedback': (context) => const FeedbackPage(),
        '/upload': (context) => const FileUploadPage(),
        '/formula': (context) => const FormulaPage(),
        '/class1': (context) => const Class1Page(),
        '/class2': (context) => const Class2Page(),
        '/class3': (context) => const Class3Page(),
        '/class4': (context) => const Class4Page(),
        '/class5': (context) => const Class5Page(),
        '/class6': (context) => const Class6Page(),
        '/class7': (context) => const Class7Page(),
        '/class8': (context) => const Class8Page(),
        '/ssc': (context) => const SSCPage(),
        '/hsc': (context) => const HSCPage(),
        '/seven_college_mathematics': (context) =>
            const SevecCollegeMathematicsPage(),
        '/info': (context) => const InfoPage(),
        '/national_university': (context) => const NationalUniversityPage(),
        '/national_university/mathematics': (context) =>
            const NuMathematicsPage(),
        '/national_university/physics': (context) => const NuPhysicsPage(),
        '/national_university/chemistry': (context) => const NuChemistryPage(),
        '/nu_statistics': (context) => const NuStatisticsPage(),
        '/nu_economics': (context) => const NuEconomicsPage(),
        '/nu_accounting': (context) => const NuAccountingPage(),
        '/nu_management': (context) => const NuManagementPage(),
        '/nu_english': (context) => const NuEnglishPage(),
        '/nu_bangla': (context) => const NuBanglaPage(),
        '/nu_history': (context) => const NuHistoryPage(),
        '/nu_islamic_studies': (context) => const NuIslamicStudiesPage(),
        '/seven_college': (context) => const SevenCollegePage(),
        '/nursing_admission': (context) => const NursingAdmissionPage(),
        '/nursing': (context) => const NursingPage(),
        '/books': (context) => const BooksPage(),
        '/class1_bangla': (context) => const Class1BanglaPage(),
        '/class1_english': (context) => const Class1EnglishPage(),
        '/class1_math': (context) => const Class1MathPage(),
        '/class2_bangla': (context) => const Class2BanglaPage(),
        '/class2_english': (context) => const Class2EnglishPage(),
        '/class2_math': (context) => const Class2MathPage(),
        '/class3_bangla': (context) => const Class3BanglaPage(),
        '/class3_english': (context) => const Class3EnglishPage(),
        '/class3_math': (context) => const Class3MathPage(),
        '/class3_science': (context) => const Class3SciencePage(),
        '/class3_social_science': (context) => const Class3SocialSciencePage(),
        '/class3_religion': (context) => const Class3ReligionPage(),
        '/class4_bangla': (context) => const Class4BanglaPage(),
        '/class4_english': (context) => const Class4EnglishPage(),
        '/class4_math': (context) => const Class4MathPage(),
        '/class4_science': (context) => const Class4SciencePage(),
        '/class4_social_science': (context) => const Class4SocialSciencePage(),
        '/class4_religion': (context) => const Class4ReligionPage(),
        '/class5_bangla': (context) => const Class5BanglaPage(),
        '/class5_english': (context) => const Class5EnglishPage(),
        '/class5_math': (context) => const Class5MathPage(),
        '/class5_science': (context) => const Class5SciencePage(),
        '/class5_social_science': (context) => const Class5SocialSciencePage(),
        '/class5_religion': (context) => const Class5ReligionPage(),
        '/class6_bangla': (context) => const Class6BanglaPage(),
        '/class6_english': (context) => const Class6EnglishPage(),
        '/class6_math': (context) => const Class6MathPage(),
        '/suggestions': (context) => const SuggestionsPage(),
        '/universities': (context) => UniversitiesPage(),
        '/engineering_universities': (context) =>
            const EngineeringUniversitiesPage(),
        '/gst': (context) => const GSTPage(),
        '/medical': (context) => const MedicalPage(),
        '/seven_college_admission': (context) =>
            const SevenCollegeAdmissionPage(),
        '/bookmarks': (context) => const BookmarksPage(),
        '/downloaded': (context) => const DownloadedPapersPage(),
        '/pdf_reader': (context) => const PdfReaderPage(),
        '/hand_notes': (context) => const HandNotesPage(),

        // SSC Subject Routes
        '/ssc_bangla_1st': (context) => const SSCBanglaFirstPaper(),
        '/ssc_bangla_2nd': (context) => const SSCBanglaSecondPaper(),
        '/ssc_english_1st': (context) => const SSCEnglishFirstPaper(),
        '/ssc_english_2nd': (context) => const SSCEnglishSecondPaper(),
        '/ssc_math': (context) => const SSCMathematics(),
        '/ssc_higher_math': (context) => const SSCHigherMath(),
        '/ssc_physics': (context) => const SSCPhysics(),
        '/ssc_chemistry': (context) => const SSCChemistry(),
        '/ssc_biology': (context) => const SSCBiology(),
        '/ssc_bangla_literature': (context) => const SSCBanglaLiterature(),
        '/ssc_bgst': (context) => const SSCBangladeshGlobalStudies(),
        '/ssc_ict': (context) => const SSCICT(),
        '/ssc_history': (context) => const SSCHistory(),
        '/ssc_geography': (context) => const SSCGeography(),
        '/ssc_civics': (context) => const SSCCivics(),
        '/ssc_religion': (context) => const SSCReligion(),
        '/ssc_accounting': (context) => const SSCAccounting(),
        '/ssc_finance': (context) => const SSCFinance(),
        '/ssc_business': (context) => const SSCBusiness(),
        '/ssc_economics': (context) => const SSCEconomics(),

        // HSC Subject Routes
        '/hsc_bangla_1st': (context) => const HSCBanglaFirstPaper(),
        '/hsc_bangla_2nd': (context) => const HSCBanglaSecondPaper(),
        '/hsc_english_1st': (context) => const HSCEnglishFirstPaper(),
        '/hsc_english_2nd': (context) => const HSCEnglishSecondPaper(),
        '/hsc_physics_1st': (context) => const HSCPhysicsFirstPaper(),
        '/hsc_physics_2nd': (context) => const HSCPhysicsSecondPaper(),
        '/hsc_chemistry_1st': (context) => const HSCChemistryFirstPaper(),
        '/hsc_chemistry_2nd': (context) => const HSCChemistrySecondPaper(),
        '/hsc_biology_1st': (context) => const HSCBiologyFirstPaper(),
        '/hsc_biology_2nd': (context) => const HSCBiologySecondPaper(),
        '/hsc_math_1st': (context) => const HSCHigherMathFirstPaper(),
        '/hsc_math_2nd': (context) => const HSCHigherMathSecondPaper(),
        '/hsc_history_1st': (context) => const HSCHistoryFirstPaper(),
        '/hsc_history_2nd': (context) => const HSCHistorySecondPaper(),
        '/hsc_geography_1st': (context) => const HSCGeographyFirstPaper(),
        '/hsc_geography_2nd': (context) => const HSCGeographySecondPaper(),
        '/hsc_economics_1st': (context) => const HSCEconomicsFirstPaper(),
        '/hsc_economics_2nd': (context) => const HSCEconomicsSecondPaper(),
        '/hsc_accounting_1st': (context) => const HSCAccountingFirstPaper(),
        '/hsc_accounting_2nd': (context) => const HSCAccountingSecondPaper(),
        '/hsc_business_org_1st': (context) => const HSCBusinessOrgFirstPaper(),
        '/hsc_business_org_2nd': (context) => const HSCBusinessOrgSecondPaper(),
        '/hsc_production': (context) => const HSCProductionManagement(),
        '/hsc_ict': (context) => const HSCICT(),

        // Class 7 Routes
        '/class7_bangla': (context) => const Class7BanglaPage(),
        '/class7_english': (context) => const Class7EnglishPage(),
        '/class7_math': (context) => const Class7MathPage(),
        '/class7_science_inquiry': (context) =>
            const Class7ScienceInquiryPage(),
        '/class7_social_science': (context) => const Class7SocialSciencePage(),
        '/class7_islam': (context) => const Class7IslamicStudiesPage(),

        // Class 8 Routes
        '/class8_bangla': (context) => const Class8BanglaPage(),
        '/class8_english': (context) => const Class8EnglishPage(),
        '/class8_math': (context) => const Class8MathPage(),
        '/class8_science_inquiry': (context) =>
            const Class8ScienceInquiryPage(),
        '/class8_social_science': (context) => const Class8SocialSciencePage(),
        '/class8_islam': (context) => const Class8IslamicStudiesPage(),

        // Class 6 Routes
        '/class6_arts_culture': (context) => const Class6ArtsCulturePage(),
        '/class6_islam': (context) => const Class6IslamicStudiesPage(),
        '/class6_science': (context) => const Class6SciencePage(),

        // Universities Routes
        '/dhaka_university': (context) => const DhakaUniversityPage(),
        '/rajshahi_university': (context) => const RajshahiUniversityPage(),
        '/chittagong_university': (context) => const ChittagongUniversityPage(),
        '/jahangirnagar_university': (context) =>
            const JahangirnagarUniversityPage(),

        // Engineering University Routes
        '/buet': (context) => const BUETPage(),
        '/cuet': (context) => const CUETPage(),
        '/ruet': (context) => const RUETPage(),
        '/kuet': (context) => const KUETPage(),
        '/duet': (context) => const DUETPage(),
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _page = 2; // Start with Home (now at index 2) selected

  final List<Widget> _pages = [
    const OnlineClassPage(),
    const BlogPage(),
    const HomePage(),
    const ToolsPage(),
    const AIPage(),
  ];

  // Define gradient colors for each navigation item
  final List<List<Color>> _navGradients = [
    [
      const Color(0xFF6C5CE7),
      const Color(0xFFA29BFE)
    ], // Purple gradient for Online Class
    [
      const Color(0xFF00B894),
      const Color(0xFF00CEC9)
    ], // Teal gradient for Blog
    [
      const Color(0xFFE17055),
      const Color(0xFFE84393)
    ], // Orange-Pink gradient for Home
    [
      const Color(0xFF0984E3),
      const Color(0xFF74B9FF)
    ], // Blue gradient for Tools
    [
      const Color(0xFFE84393),
      const Color(0xFFAD7BFF)
    ], // Pink-Purple gradient for AI
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          return;
        }
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else if (_page != 2) {
          setState(() {
            _page = 2;
          });
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        extendBody: false,
        bottomNavigationBar: CustomBottomNavigationBar(
          currentPageIndex: _page,
          onPageSelected: (index) {
            FocusManager.instance.primaryFocus?.unfocus(); // Unfocus keyboard
            setState(() {
              _page = index;
            });
          },
          navGradients: _navGradients,
        ),
        body: Stack(
          children: [
            // Animated background blur circles
            Positioned(
              top: -50,
              right: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            Positioned(
              bottom: -80,
              left: -80,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              top: 100,
              left: -30,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            // Main content with subtle blur overlay
            ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                  ),
                  child: _pages[_page],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
