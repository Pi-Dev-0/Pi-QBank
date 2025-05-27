class Class {
  final String name;
  final List<Subject> subjects;

  Class({required this.name, required this.subjects});
}

class Subject {
  final String name;
  final List<String> chapters;

  Subject({required this.name, this.chapters = const []});
}

class Video {
  final String title;
  final String youtubeUrl;
  final String thumbnailUrl;
  final String className;
  final String subjectName;
  final String chapterName;

  Video({
    required this.title,
    required this.youtubeUrl,
    required this.thumbnailUrl,
    required this.className,
    required this.subjectName,
    required this.chapterName,
  });

  factory Video.fromJson(Map<String, dynamic> json) {
    return Video(
      title: json['title'] ?? 'No Title',
      youtubeUrl: json['youtubeUrl'] ?? '',
      thumbnailUrl: json['thumbnailUrl'] ?? '',
      className: json['className'] ?? 'Unknown Class',
      subjectName: json['subjectName'] ?? 'Unknown Subject',
      chapterName: json['chapterName'] ?? 'Unknown Chapter',
    );
  }
}
