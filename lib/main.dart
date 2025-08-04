// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  // Fetch the available cameras before initializing the app.
  try {
    WidgetsFlutterBinding.ensureInitialized();
    // orientation lock
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _cameras = await availableCameras();
  } on CameraException catch (e) {
    _logError(e.code, e.description);
  }
  runApp(const CameraApp());
}

/// Camera example home widget.
class CameraExampleHome extends StatefulWidget {
  /// Default Constructor
  const CameraExampleHome({super.key});

  @override
  State<CameraExampleHome> createState() {
    return _CameraExampleHomeState();
  }
}

/// Returns a suitable camera icon for [direction].
IconData getCameraLensIcon(CameraLensDirection direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear;
    case CameraLensDirection.front:
      return Icons.camera_front;
    case CameraLensDirection.external:
      return Icons.camera;
  }
  // This enum is from a different package, so a new value could be added at
  // any time. The example should keep working if that happens.
  // ignore: dead_code
  return Icons.camera;
}

void _logError(String code, String? message) {
  // ignore: avoid_print
  print('Error: $code${message == null ? '' : '\nError Message: $message'}');
}

class _CameraExampleHomeState extends State<CameraExampleHome>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? controller;
  XFile? imageFile;
  XFile? videoFile;
  VoidCallback? videoPlayerListener;
  bool enableAudio = true;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentScale = 1.0;
  double _baseScale = 1.0;
  late final AnimationController _focusModeControlRowAnimationController;
  late final CurvedAnimation _focusModeControlRowAnimation;
  // Counting pointers (number of user fingers on screen)
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _focusModeControlRowAnimation = CurvedAnimation(
      parent: _focusModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );
    _initializeCameraController(cameras.first);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    _focusModeControlRowAnimationController.dispose();
    _focusModeControlRowAnimation.dispose();

    super.dispose();
  }

  // #docregion AppLifecycle
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
      _initializeCameraController(cameraController.description);
    }
  }

  // #enddocregion AppLifecycle
  double _currentZoom = 1.0;
  final List<double> _zoomLevels = [1.0, 4.0, 8.0];

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _cameraPreviewWidget()),
          // Zoom indicator
          Positioned(
            bottom: 120,
            left: 0,
            right: 0,
            child: Center(
              child: ZoomIndicator(
                currentZoom: _currentZoom,
                zoomLevels: _zoomLevels,
                onZoomChanged: (double zoom) {
                  if (zoom == 0.5) {
                    controller!.setZoomLevel(_minAvailableZoom);
                    setState(() {
                      _currentZoom = 0.5;
                    });
                    return;
                  }
                  setState(() {
                    controller!.setZoomLevel(zoom);
                    _currentZoom = zoom;
                  });
                },
              ),
            ),
          ),
          // Camera button
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: CaptureButton(
                onPressed: () {
                  if (controller != null && controller!.value.isInitialized) {
                    onTakePictureButtonPressed();
                  }
                },
              ),
            ),
          ),
          // Flash button
          Positioned(
            bottom: 50,
            left: 50,
            child: FlashButton(color: Colors.white, controller: controller!),
          ),
          Positioned(
            top: 20,
            left: 4,
            child: BackButton(
              color: Colors.white,
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  void onFocusModeButtonPressed(Offset offset, BoxConstraints constraints) {
    if (_focusModeControlRowAnimationController.value == 1) {
      _focusModeControlRowAnimationController.reverse();
    } else {
      _focusModeControlRowAnimationController.forward();
    }

    controller!.setFocusPoint(offset);
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return Listener(
        onPointerDown: (_) => _pointers++,
        onPointerUp: (PointerUpEvent event) {
          final constraints = BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width,
            maxHeight: MediaQuery.of(context).size.height,
          );
          _pointers--;
          final offset = Offset(
            event.localPosition.dx / constraints.maxWidth,
            event.localPosition.dy / constraints.maxHeight,
          );
          onFocusModeButtonPressed(offset, constraints);
        },
        child: CameraPreview(
          controller!,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                onTapDown: (TapDownDetails details) =>
                    onViewFinderTap(details, constraints),
              );
            },
          ),
        ),
      );
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    try {
      // When there are not exactly two fingers on screen don't scale
      if (controller == null || _pointers != 2) {
        return;
      }

      _currentScale = (_baseScale * details.scale).clamp(
        _minAvailableZoom,
        _maxAvailableZoom,
      );

      await controller!.setZoomLevel(_currentScale);
      final zoom = double.parse(_currentScale.toStringAsPrecision(2));
      if (_zoomLevels.contains(zoom)) {
        setState(() {
          _currentZoom = zoom;
        });
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (controller == null) {
      return;
    }

    final CameraController cameraController = controller!;

    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      return controller!.setDescription(cameraDescription);
    } else {
      return _initializeCameraController(cameraDescription);
    }
  }

  Future<void> _initializeCameraController(
    CameraDescription cameraDescription,
  ) async {
    final CameraController cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.ultraHigh,
      enableAudio: enableAudio,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    controller = cameraController;

    // If the controller is updated then update the UI.
    cameraController.addListener(() {
      if (mounted) {
        setState(() {});
      }
      if (cameraController.value.hasError) {
        showInSnackBar(
          'Camera error ${cameraController.value.errorDescription}',
        );
      }
    });

    try {
      await cameraController.initialize();
      await Future.wait(<Future<Object?>>[
        // The exposure mode is currently not supported on the web.
        cameraController.getMaxZoomLevel().then((double value) {
          print('maxAvailableZoom: $value');
          return _maxAvailableZoom = value;
        }),
        cameraController.getMinZoomLevel().then((double value) {
          print('minAvailableZoom: $value');
          if (value < 1.0) {
            setState(() {
              _zoomLevels.insert(0, 0.5);
            });
          }
          return _minAvailableZoom = value;
        }),
      ]);
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          showInSnackBar('You have denied camera access.');
        case 'CameraAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable camera access.');
        case 'CameraAccessRestricted':
          // iOS only
          showInSnackBar('Camera access is restricted.');
        case 'AudioAccessDenied':
          showInSnackBar('You have denied audio access.');
        case 'AudioAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable audio access.');
        case 'AudioAccessRestricted':
          // iOS only
          showInSnackBar('Audio access is restricted.');
        default:
          _showCameraException(e);
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> onTakePictureButtonPressed() async {
    final XFile? file = await takePicture();
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ImagePreview(image: file!)),
      );
    }
  }

  Future<void> onCaptureOrientationLockButtonPressed() async {
    try {
      if (controller != null) {
        final CameraController cameraController = controller!;
        if (cameraController.value.isCaptureOrientationLocked) {
          await cameraController.unlockCaptureOrientation();
          showInSnackBar('Capture orientation unlocked');
        } else {
          await cameraController.lockCaptureOrientation();
          showInSnackBar(
            'Capture orientation locked to ${cameraController.value.lockedCaptureOrientation.toString().split('.').last}',
          );
        }
      }
    } on CameraException catch (e) {
      _showCameraException(e);
    }
  }

  void onSetFocusModeButtonPressed(FocusMode mode) {
    setFocusMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      showInSnackBar('Focus mode set to ${mode.toString().split('.').last}');
    });
  }

  Future<void> setFocusMode(FocusMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setFocusMode(mode);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      final XFile file = await cameraController.takePicture();
      return file;
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  void _showCameraException(CameraException e) {
    _logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }
}

/// CameraApp is the Main Application.
class CameraApp extends StatelessWidget {
  /// Default Constructor
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: CameraExampleHome());
  }
}

/// Getting available cameras for testing.
@visibleForTesting
List<CameraDescription> get cameras => _cameras;
List<CameraDescription> _cameras = <CameraDescription>[];

class CaptureButton extends StatefulWidget {
  final VoidCallback onPressed;
  const CaptureButton({super.key, required this.onPressed});

  @override
  State<CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<CaptureButton> {
  bool isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isIOS = Platform.isIOS;
    Widget androidCaptureButton = Container(
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
    );

    Widget iosCaptureButton = Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
      ),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
      ),
    );

    return GestureDetector(
        onTap: isPressed
            ? null
            : () {
                setState(() {
                  isPressed = true;
                });
                HapticFeedback.lightImpact();
                widget.onPressed();
                Future.delayed(const Duration(milliseconds: 3000), () {
                  if (mounted) {
                    setState(() {
                      isPressed = false;
                    });
                  }
                });
              },
        child: isIOS ? iosCaptureButton : androidCaptureButton);
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
            onTap: () {
              HapticFeedback.lightImpact();
              onZoomChanged(zoom);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color:
                    isSelected ? const Color(0xFFD4AF37) : Colors.transparent,
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

class FlashButton extends StatefulWidget {
  final CameraController controller;
  final Color? color;
  const FlashButton(
      {super.key, required this.controller, this.color = Colors.white});

  @override
  State<FlashButton> createState() => FlashButtonState();
}

class FlashButtonState extends State<FlashButton> {
  List<FlashMode> flashModes = [
    FlashMode.auto,
    FlashMode.always,
    FlashMode.off,
    FlashMode.torch,
  ];

  final flashIcons = [
    Icons.flash_auto,
    Icons.flash_on,
    Icons.flash_off,
    Icons.flashlight_on,
  ];

  FlashMode _currentFlashMode = FlashMode.auto;

  int _currentFlashModeIndex = 0;

  void _toggleFlashMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _currentFlashModeIndex = (_currentFlashModeIndex + 1) % flashModes.length;
      _currentFlashMode = flashModes[_currentFlashModeIndex];
    });
    widget.controller.setFlashMode(_currentFlashMode);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        flashIcons[_currentFlashModeIndex],
        color: widget.color,
      ),
      onPressed: _toggleFlashMode,
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
