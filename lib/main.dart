import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _cameras = await availableCameras();
  runApp(const CameraApp());
}

class CameraApp extends StatefulWidget {
  const CameraApp({super.key});

  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: CameraWidget());
  }
}

/// CameraWidget is the Main Application.
class CameraWidget extends StatefulWidget {
  /// Default Constructor
  const CameraWidget({super.key});

  @override
  State<CameraWidget> createState() => _CameraWidgetState();
}

class _CameraWidgetState extends State<CameraWidget> {
  late CameraController controller;
  double _currentZoom = 1.0;
  final List<double> _zoomLevels = [0.5, 1.0, 2.0];

  @override
  void initState() {
    super.initState();
    controller = CameraController(_cameras[0], ResolutionPreset.ultraHigh);
    controller
        .initialize()
        .then((_) {
          if (!mounted) {
            return;
          }
          setState(() {});
        })
        .catchError((Object e) {
          if (e is CameraException) {
            switch (e.code) {
              case 'CameraAccessDenied':
                // Handle access errors here.
                break;
              default:
                // Handle other errors here.
                break;
            }
          }
        });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _setZoom(double zoom) {
    setState(() {
      _currentZoom = zoom;
    });
    controller.setZoomLevel(zoom);
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(controller)),
          // Zoom indicator
          Positioned(
            bottom: 140,
            left: 0,
            right: 0,
            child: Center(
              child: ZoomIndicator(
                currentZoom: _currentZoom,
                zoomLevels: _zoomLevels,
                onZoomChanged: _setZoom,
              ),
            ),
          ),
          // Camera button
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: CameraButton(
                onPressed: () async {
                  try {
                    final image = await controller.takePicture();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ImagePreview(image: image),
                      ),
                    );
                    // Handle the captured image here
                    print('Picture saved to ${image.path}');
                  } catch (e) {
                    print('Error taking picture: $e');
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CameraButton extends StatelessWidget {
  final VoidCallback onPressed;
  const CameraButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red,
          ),
        ),
      ),
    );
  }
}

class ZoomIndicator extends StatelessWidget {
  final double currentZoom;
  final List<double> zoomLevels;
  final Function(double) onZoomChanged;

  const ZoomIndicator({
    super.key,
    required this.currentZoom,
    required this.zoomLevels,
    required this.onZoomChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: zoomLevels.map((zoom) {
          final isSelected = zoom == currentZoom;
          return GestureDetector(
            onTap: () => onZoomChanged(zoom),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFD4AF37)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                zoom == 0.5
                    ? '.5'
                    : zoom == 1.0
                    ? '1x'
                    : '${zoom.toInt()}',
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class ImagePreview extends StatefulWidget {
  final XFile image;
  const ImagePreview({super.key, required this.image});

  @override
  State<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<ImagePreview> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Image Preview')),
      body: Image.file(File(widget.image.path)),
    );
  }
}
