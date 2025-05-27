class AppConfig {
  static const String apiKey =
      String.fromEnvironment('API_KEY', defaultValue: '');
  static const String baseUrl =
      String.fromEnvironment('BASE_URL', defaultValue: '');
  static const String endpointApi = String.fromEnvironment('ENDPOINT_API');
  static const String fileIoApiKey = String.fromEnvironment('FILE_IO_API_KEY');
  static const String notificationApi =
      String.fromEnvironment('NOTIFICATION_API');
  static const String youtubeApiKey =
      String.fromEnvironment('YOUTUBE_API_KEY');
  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY');
  static const String fileUploadApi =
      String.fromEnvironment('UPLOADCARE_PUBLIC_KEY');
  static const String uploadBase = String.fromEnvironment('UPLOADCARE_BASE_URL');
  static const String guideBookApi = String.fromEnvironment('GUIDE_BOOK_API');
  static const String booksApi = String.fromEnvironment('BOOKS_API');
  static const String class1Api = String.fromEnvironment('CLASS1_API');
  static const String class2Api = String.fromEnvironment('CLASS2_API');
  static const String class3Api = String.fromEnvironment('CLASS3_API');
  static const String class4Api = String.fromEnvironment('CLASS4_API');
  static const String class5Api = String.fromEnvironment('CLASS5_API');
  static const String class6Api = String.fromEnvironment('CLASS6_API');
  static const String class7Api = String.fromEnvironment('CLASS7_API');
  static const String class8Api = String.fromEnvironment('CLASS8_API');
  static const String sscApi = String.fromEnvironment('SSC_API');
  static const String hscApi = String.fromEnvironment('HSC_API');
  static const String formulaApi = String.fromEnvironment('FORMULA_API');
  static const String suggestionApi = String.fromEnvironment('SUGGESTION_API');
  static const String sevenCollegeAdmissionApi =
      String.fromEnvironment('SEVEN_COLLEGE_ADMISSION_API');
  static const String gstApi = String.fromEnvironment('GST_API');
  static const String medicalApi = String.fromEnvironment('MEDICAL_API');
  static const String nursingApi = String.fromEnvironment('NURSING_API');
  static const String nursingAdmissionApi =
      String.fromEnvironment('NURSING_ADMISSION_API');
  static const String sevenCollegeMathApi =
      String.fromEnvironment('SEVEN_COLLEGE_MATH_API');
  static const String universityAdmissionApi =
      String.fromEnvironment('UNIVERSITY_ADMISSION_API');
  static const String engineeringUniversityAdmissionApi =
      String.fromEnvironment('ENGINEERING_UNIVERSITY_ADMISSION_API');
  static const String nationalUniversityApi =
      String.fromEnvironment('NATIONAL_UNIVERSITY_API');
  static const String nuMathematicsApi=
      String.fromEnvironment('NU_MATHEMATICS_API');
  static const String nuManagementApi =
      String.fromEnvironment('NU_MANAGEMENT_API');
  static const String nuMarketingApi =
      String.fromEnvironment('NU_MARKETING_API');
  static const String nuAccountingApi =
      String.fromEnvironment('NU_ACCOUNTING_API');
  static const String nuEconomicsApi =
      String.fromEnvironment('NU_ECONOMICS_API');
  static const String nuFinanceApi =
      String.fromEnvironment('NU_FINANCE_API');
  static const String nuZoologyApi =
      String.fromEnvironment('NU_ZOOLOGY_API');
  static const String nuBotanyApi = 
      String.fromEnvironment('NU_BOTANY_API');
  static const String nuPhysicsApi =
      String.fromEnvironment('NU_PHYSICS_API');
  static const String nuChemistryApi =
      String.fromEnvironment('NU_CHEMISTRY_API');
  static const String nuBanglaApi =
      String.fromEnvironment('NU_BANGLA_API');
  static const String nuEnglishApi =
      String.fromEnvironment('NU_ENGLISH_API');
  static const String nuHistoryApi =
      String.fromEnvironment('NU_HISTORY_API');
  static const String nuGeographyApi =
      String.fromEnvironment('NU_GEOGRAPHY_API');
  static const String nuStatisticsApi =
      String.fromEnvironment('NU_STATISTICS_API');
  static const String nuPoliticalScienceApi =
      String.fromEnvironment('NU_POLITICAL_SCIENCE_API');
  static const String nuSociologyApi =
      String.fromEnvironment('NU_SOCIOLOGY_API');
  static const String nuIslamicStudiesApi =
      String.fromEnvironment('NU_ISLAMIC_STUDIES_API');

  // Add more configuration values as needed

  // Validate if all required environment variables are set
  static bool validateConfig() {
    return apiKey.isNotEmpty &&
        baseUrl.isNotEmpty &&
        endpointApi.isNotEmpty &&
        fileIoApiKey.isNotEmpty &&
        notificationApi.isNotEmpty;
  }
}
