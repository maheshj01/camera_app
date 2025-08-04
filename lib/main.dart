import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class _CameraWidgetState extends State<CameraWidget>
    with WidgetsBindingObserver {
  late CameraController controller;
  double _currentZoom = 1.0;
  final List<double> _zoomLevels = [0.5, 1.0, 4.0, 8.0];
  late CameraDescription _currentCamera;
  bool _isSwitchingCamera = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start with the main camera (usually index 0)
    _currentCamera = _cameras[0];
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  void _initializeCamera() {
    controller = CameraController(_currentCamera, ResolutionPreset.ultraHigh);
    controller
        .initialize()
        .then((_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isSwitchingCamera = false;
          });
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
          setState(() {
            _isSwitchingCamera = false;
          });
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  Future<void> _setZoom(double zoom) async {
    setState(() {
      _currentZoom = zoom;
    });

    // Switch to ultra-wide camera for 0.5x zoom
    if (zoom == 0.5) {
      final length = _cameras.length;
      print('length: $length ${_cameras.last.lensDirection} ');
      // Use the last back camera (typically ultra-wide)
      if (length > 1) {
        final targetCamera = _cameras.lastWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () {
            print('no back camera found');
            return _cameras[0];
          },
        );

        if (targetCamera != _currentCamera) {
          setState(() {
            _isSwitchingCamera = true;
          });

          await controller.dispose();
          _currentCamera = targetCamera;
          _initializeCamera();
          print('targetCamera: $targetCamera');
          return;
        }
      }
    } else {
      // Switch back to main camera for other zoom levels
      if (_currentCamera != _cameras[0]) {
        setState(() {
          _isSwitchingCamera = true;
        });

        await controller.dispose();
        _currentCamera = _cameras[0];
        _initializeCamera();
        // Set the digital zoom after camera switch
        Future.delayed(const Duration(milliseconds: 200), () {
          if (controller.value.isInitialized) {
            controller.setZoomLevel(zoom);
          }
        });
        return;
      }

      // For main camera, use digital zoom
      if (controller.value.isInitialized) {
        controller.setZoomLevel(zoom);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized || _isSwitchingCamera) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
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
                  HapticFeedback.lightImpact();
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
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 6),
        ),
        child: Container(
          margin: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
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
