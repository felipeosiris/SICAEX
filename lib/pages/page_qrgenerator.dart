import 'package:flutter/material.dart';
import 'package:SICAE/components/components.dart';
import 'package:SICAE/utils/max_width_extension.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrgeneratorPage extends StatelessWidget {
  static const String name = 'qrgenerator';

  QrgeneratorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final TextEditingController _controller = TextEditingController();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomScrollView(
        slivers: [
          SliverList.list(
            children: [
              const MinimalMenuBar(),
              Align(
                alignment: Alignment.center,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.qr_code,
                        size: 250,
                        color: Colors.blueGrey,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Generar código QR",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Ingrese el nombre del alumno...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          if (_controller.text.isNotEmpty) {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                content: QrImageView(
                                  data: _controller.text,
                                  version: QrVersions.auto,
                                  size: 200.0,
                                ),
                              ),
                            );
                          }
                        },
                        child: Text('Generar QR'),
                      ),
                    ],
                  ),
                ),
              ),
            ].toMaxWidth(),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: MaxWidthBox(
                maxWidth: 1200,
                backgroundColor: Colors.white,
                child: Container()),
          ),
          ...[
            divider,
            const Footer(),
          ].toMaxWidthSliver(),
        ],
      ),
    );
  }
}
