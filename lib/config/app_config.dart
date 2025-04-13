class AppConfig {
  static const String apiKey =
      String.fromEnvironment('API_KEY', defaultValue: '');
  static const String baseUrl =
      String.fromEnvironment('BASE_URL', defaultValue: '');
  static const String endpointApi = String.fromEnvironment('ENDPOINT_API');
  static const String fileIoApiKey = String.fromEnvironment('FILE_IO_API_KEY');
  static const String notificationApi =
      String.fromEnvironment('NOTIFICATION_API');
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
