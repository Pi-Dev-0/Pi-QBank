import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';

class NotesRemainderPage extends StatelessWidget {
  const NotesRemainderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Notes & Remainder',
      ),
      body: Center(
        child: Text(
          'Notes & Remainder functionality will be implemented here!',
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}