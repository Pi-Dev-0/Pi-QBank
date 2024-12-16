// Import all subject pages
import 'bangla_first_paper.dart';
import 'bangla_second_paper.dart';
import 'english_first_paper.dart';
import 'english_second_paper.dart';
import 'physics_first_paper.dart';
import 'physics_second_paper.dart';
import 'chemistry_first_paper.dart';
import 'chemistry_second_paper.dart';
import 'biology_first_paper.dart';
import 'biology_second_paper.dart';
import 'higher_math_first_paper.dart';
import 'higher_math_second_paper.dart';
import 'ict.dart';
import 'history_first_paper.dart';
import 'history_second_paper.dart';
import 'geography_first_paper.dart';
import 'geography_second_paper.dart';
import 'economics_first_paper.dart';
import 'economics_second_paper.dart';
import 'business_org_first_paper.dart';
import 'business_org_second_paper.dart';
import 'accounting_first_paper.dart';
import 'accounting_second_paper.dart';
import 'production_management.dart';

// Export all subject pages
export 'bangla_first_paper.dart';
export 'bangla_second_paper.dart';
export 'english_first_paper.dart';
export 'english_second_paper.dart';
export 'physics_first_paper.dart';
export 'physics_second_paper.dart';
export 'chemistry_first_paper.dart';
export 'chemistry_second_paper.dart';
export 'biology_first_paper.dart';
export 'biology_second_paper.dart';
export 'higher_math_first_paper.dart';
export 'higher_math_second_paper.dart';
export 'ict.dart';
export 'history_first_paper.dart';
export 'history_second_paper.dart';
export 'geography_first_paper.dart';
export 'geography_second_paper.dart';
export 'economics_first_paper.dart';
export 'economics_second_paper.dart';
export 'business_org_first_paper.dart';
export 'business_org_second_paper.dart';
export 'accounting_first_paper.dart';
export 'accounting_second_paper.dart';
export 'production_management.dart';

// Subject information for easy access
final List<Map<String, dynamic>> hscSubjects = [
  {
    'name': 'বাংলা ১ম পত্র',
    'code': 'BAN1',
    'widget': const HSCBanglaFirstPaper(),
  },
  {
    'name': 'বাংলা ২য় পত্র',
    'code': 'BAN2',
    'widget': const HSCBanglaSecondPaper(),
  },
  {
    'name': 'English 1st Paper',
    'code': 'ENG1',
    'widget': const HSCEnglishFirstPaper(),
  },
  {
    'name': 'English 2nd Paper',
    'code': 'ENG2',
    'widget': const HSCEnglishSecondPaper(),
  },
  // Science Group
  {
    'name': 'পদার্থবিজ্ঞান ১ম পত্র',
    'code': 'PHY1',
    'widget': const HSCPhysicsFirstPaper(),
  },
  {
    'name': 'পদার্থবিজ্ঞান ২য় পত্র',
    'code': 'PHY2',
    'widget': const HSCPhysicsSecondPaper(),
  },
  {
    'name': 'রসায়ন ১ম পত্র',
    'code': 'CHEM1',
    'widget': const HSCChemistryFirstPaper(),
  },
  {
    'name': 'রসায়ন ২য় পত্র',
    'code': 'CHEM2',
    'widget': const HSCChemistrySecondPaper(),
  },
  {
    'name': 'জীববিজ্ঞান ১ম পত্র',
    'code': 'BIO1',
    'widget': const HSCBiologyFirstPaper(),
  },
  {
    'name': 'জীববিজ্ঞান ২য় পত্র',
    'code': 'BIO2',
    'widget': const HSCBiologySecondPaper(),
  },
  {
    'name': 'উচ্চতর গণিত ১ম পত্র',
    'code': 'HMATH1',
    'widget': const HSCHigherMathFirstPaper(),
  },
  {
    'name': 'উচ্চতর গণিত ২য় পত্র',
    'code': 'HMATH2',
    'widget': const HSCHigherMathSecondPaper(),
  },
  // Humanities Group
  {
    'name': 'ইতিহাস ১ম পত্র',
    'code': 'HIST1',
    'widget': const HSCHistoryFirstPaper(),
  },
  {
    'name': 'ইতিহাস ২য় পত্র',
    'code': 'HIST2',
    'widget': const HSCHistorySecondPaper(),
  },
  {
    'name': 'ভূগোল ১ম পত্র',
    'code': 'GEO1',
    'widget': const HSCGeographyFirstPaper(),
  },
  {
    'name': 'ভূগোল ২য় পত্র',
    'code': 'GEO2',
    'widget': const HSCGeographySecondPaper(),
  },
  {
    'name': 'অর্থনীতি ১ম পত্র',
    'code': 'ECON1',
    'widget': const HSCEconomicsFirstPaper(),
  },
  {
    'name': 'অর্থনীতি ২য় পত্র',
    'code': 'ECON2',
    'widget': const HSCEconomicsSecondPaper(),
  },
  {
    'name': 'তথ্য ও যোগাযোগ প্রযুক্তি',
    'code': 'ICT',
    'widget': const HSCICT(),
  },
  // Business Studies Group
  {
    'name': 'ব্যবসায় সংগঠন ও ব্যবস্থাপনা ১ম পত্র',
    'code': 'BOM1',
    'widget': const HSCBusinessOrgFirstPaper(),
  },
  {
    'name': 'ব্যবসায় সংগঠন ও ব্যবস্থাপনা ২য় পত্র',
    'code': 'BOM2',
    'widget': const HSCBusinessOrgSecondPaper(),
  },
  {
    'name': 'হিসাববিজ্ঞান ১ম পত্র',
    'code': 'ACC1',
    'widget': const HSCAccountingFirstPaper(),
  },
  {
    'name': 'হিসাববিজ্ঞান ২য় পত্র',
    'code': 'ACC2',
    'widget': const HSCAccountingSecondPaper(),
  },
  {
    'name': 'উৎপাদন ব্যবস্থাপনা ও বিপণন',
    'code': 'PMM',
    'widget': const HSCProductionManagement(),
  },
];
