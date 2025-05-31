import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html_parser; // Import html parser

class BlogPost {
  final String title;
  final String link;
  final String published;
  final String summary;
  final String author;
  final String content; // New field for full HTML content
  final String? imageUrl; // New optional field for the first image URL

  BlogPost({
    required this.title,
    required this.link,
    required this.published,
    required this.summary,
    required this.author,
    required this.content,
    this.imageUrl,
  });
}

class BlogService {
  static const String _feedUrl =
      'https://pi-mathematics.blogspot.com/feeds/posts/default';

  Future<List<BlogPost>> fetchBlogPosts() async {
    try {
      final response = await http.get(Uri.parse(_feedUrl));

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final entries = document.findAllElements('entry');

        return entries.map((node) {
          final title = node.findElements('title').isNotEmpty
              ? node.findElements('title').first.innerText
              : 'No Title';
          final link = node
                  .findElements('link')
                  .firstWhere(
                      (element) => element.getAttribute('rel') == 'alternate',
                      orElse: () => XmlElement(XmlName('link')))
                  .getAttribute('href') ??
              '';
          final published = node.findElements('published').isNotEmpty
              ? node.findElements('published').first.innerText
              : 'No Date';
          final summary = node.findElements('summary').isNotEmpty
              ? node.findElements('summary').first.innerText
              : 'No Summary';
          final author = node.findElements('author').isNotEmpty &&
                  node
                      .findElements('author')
                      .first
                      .findElements('name')
                      .isNotEmpty
              ? node
                  .findElements('author')
                  .first
                  .findElements('name')
                  .first
                  .innerText
              : 'Unknown Author';

          // Extract full content
          final contentElement = node.findElements('content').firstOrNull;
          final content =
              contentElement != null ? contentElement.innerText : 'No Content';

          // Extract first image URL from content
          String? imageUrl;
          if (contentElement != null) {
            final htmlDocument = html_parser.parse(content);
            final imgElements = htmlDocument.getElementsByTagName('img');
            if (imgElements.isNotEmpty) {
              imageUrl = imgElements.first.attributes['src'];
            }
          }


          return BlogPost(
            title: title,
            link: link,
            published: published,
            summary: summary,
            author: author,
            content: content,
            imageUrl: imageUrl,
          );
        }).toList();
      } else {
        throw Exception('Failed to load blog posts: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching blog posts: $e');
    }
  }
}
