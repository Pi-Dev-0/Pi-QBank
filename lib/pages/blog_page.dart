import 'package:flutter/material.dart';
import 'package:pi_qbank/services/blog_service.dart';
import 'package:pi_qbank/pages/view_post_page.dart'; // Import ViewPostPage
import 'package:pi_qbank/widgets/custom_app_bar.dart'; // Import CustomAppBar

class BlogPage extends StatefulWidget {
  const BlogPage({super.key});

  @override
  State<BlogPage> createState() => _BlogPageState();
}

class _BlogPageState extends State<BlogPage> {
  late Future<List<BlogPost>> _blogPostsFuture;

  @override
  void initState() {
    super.initState();
    _blogPostsFuture = BlogService().fetchBlogPosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Pi-QBank Blog',
      ),
      body: FutureBuilder<List<BlogPost>>(
        future: _blogPostsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No blog posts found.'));
          } else {
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final post = snapshot.data![index];
                return Card(
                  margin: const EdgeInsets.all(8.0),
                  elevation: 8.0, // Increased elevation for more shadow
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ViewPostPage(
                            title: post.title,
                            content: post.content,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Image.network(
                                  post.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const SizedBox.shrink(); // Hide if image fails to load
                                  },
                                ),
                              ),
                            ),
                          Text(
                            post.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Published: ${post.published.substring(0, 10)}', // Format date
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Author: ${post.author}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}
