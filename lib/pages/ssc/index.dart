// Import all subject pages
import 'bangla_first_paper.dart';
import 'bangla_second_paper.dart';
import 'english_first_paper.dart';
import 'english_second_paper.dart';
import 'mathematics.dart';
import 'physics.dart';
import 'chemistry.dart';
import 'biology.dart';
import 'higher_math.dart';
import 'religion.dart';
import 'ict.dart';
import 'geography.dart';
import 'history.dart';
import 'civics.dart';
import 'economics.dart';
import 'business.dart';
import 'accounting.dart';
import 'finance.dart';
import 'bangladesh_global_studies.dart';

export 'bangla_first_paper.dart';
export 'bangla_second_paper.dart';
export 'english_first_paper.dart';
export 'english_second_paper.dart';
export 'mathematics.dart';
export 'physics.dart';
export 'chemistry.dart';
export 'biology.dart';
export 'higher_math.dart';
export 'religion.dart';
export 'ict.dart';
export 'geography.dart';
export 'history.dart';
export 'civics.dart';
export 'economics.dart';
export 'business.dart';
export 'accounting.dart';
export 'finance.dart';
export 'bangladesh_global_studies.dart';

// Subject information for easy access
final List<Map<String, dynamic>> sscSubjects = [
  {
    'name': 'Bangla First Paper',
    'code': 'BAN1',
    'widget': const SSCBanglaFirstPaper(),
  },
  {
    'name': 'Bangla Second Paper',
    'code': 'BAN2',
    'widget': const SSCBanglaSecondPaper(),
  },
  {
    'name': 'English First Paper',
    'code': 'ENG1',
    'widget': const SSCEnglishFirstPaper(),
  },
  {
    'name': 'English Second Paper',
    'code': 'ENG2',
    'widget': const SSCEnglishSecondPaper(),
  },
  {
    'name': 'Mathematics',
    'code': 'MATH',
    'widget': const SSCMathematics(),
  },
  {
    'name': 'Physics',
    'code': 'PHY',
    'widget': const SSCPhysics(),
  },
  {
    'name': 'Chemistry',
    'code': 'CHEM',
    'widget': const SSCChemistry(),
  },
  {
    'name': 'Biology',
    'code': 'BIO',
    'widget': const SSCBiology(),
  },
  {
    'name': 'Higher Mathematics',
    'code': 'HMATH',
    'widget': const SSCHigherMath(),
  },
  {
    'name': 'ধর্ম ও নৈতিক শিক্ষা',
    'code': 'REL',
    'widget': const SSCReligion(),
  },
  {
    'name': 'তথ্য ও যোগাযোগ প্রযুক্তি',
    'code': 'ICT',
    'widget': const SSCICT(),
  },
  {
    'name': 'বাংলাদেশ ও বিশ্ব পরিচয়',
    'code': 'BGST',
    'widget': const SSCBangladeshGlobalStudies(),
  },
  {
    'name': 'ভূগোল',
    'code': 'GEO',
    'widget': const SSCGeography(),
  },
  {
    'name': 'ইতিহাস',
    'code': 'HIST',
    'widget': const SSCHistory(),
  },
  {
    'name': 'পৌরনীতি',
    'code': 'CIV',
    'widget': const SSCCivics(),
  },
  {
    'name': 'অর্থনীতি',
    'code': 'ECON',
    'widget': const SSCEconomics(),
  },
  {
    'name': 'ব্যবসায় উদ্যোগ',
    'code': 'BUS',
    'widget': const SSCBusiness(),
  },
  {
    'name': 'হিসাববিজ্ঞান',
    'code': 'ACC',
    'widget': const SSCAccounting(),
  },
  {
    'name': 'ফিন্যান্স ও ব্যাংকিং',
    'code': 'FIN',
    'widget': const SSCFinance(),
  },
];
