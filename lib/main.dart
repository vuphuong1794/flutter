import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();

  // Tìm camera trước (front-facing camera)
  final frontCamera = cameras.firstWhere(
    (camera) => camera.lensDirection == CameraLensDirection.front,
    orElse: () => throw Exception('No front camera found'),
  );

  runApp(MyApp(camera: frontCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drowsiness Detection',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: DrowsinessDetector(camera: camera),
    );
  }
}

class DrowsinessDetector extends StatefulWidget {
  final CameraDescription camera;

  const DrowsinessDetector({Key? key, required this.camera}) : super(key: key);

  @override
  _DrowsinessDetectorState createState() => _DrowsinessDetectorState();
}

class _DrowsinessDetectorState extends State<DrowsinessDetector> {
  CameraController? _controller;
  late Future<void> _initializeControllerFuture;
  String _status = 'Initializing...';
  String _processedImage = '';
  bool _isDetecting = false;

  final String apiUrl = 'http://192.168.5.85:5000/api/detect_drowsiness';

  @override
  void initState() {
    super.initState();
    _initializeControllerFuture = Future.value();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _controller = CameraController(
        widget.camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      _initializeControllerFuture = _controller!.initialize();
      await _initializeControllerFuture;

      if (_controller!.value.isInitialized) {
        setState(() {
          _status = 'Camera initialized';
        });
      } else {
        setState(() {
          _status = 'Error: Camera failed to initialize properly';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error initializing camera: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _detectDrowsiness() async {
    if (_isDetecting || _controller == null) {
      setState(() {
        _status =
            _controller == null
                ? 'Camera not initialized. Please wait or restart the app.'
                : 'Detection already in progress';
      });
      return;
    }

    if (!_controller!.value.isInitialized) {
      setState(() {
        _status = 'Error: Camera is not initialized';
      });
      return;
    }

    setState(() {
      _isDetecting = true;
      _status = 'Detecting...';
      _processedImage = '';
    });

    try {
      await _initializeControllerFuture;

      // Log camera state for debugging
      debugPrint('Camera state before taking picture:');
      debugPrint('isInitialized: ${_controller!.value.isInitialized}');
      debugPrint('isPreviewPaused: ${_controller!.value.isPreviewPaused}');
      debugPrint('isRecordingVideo: ${_controller!.value.isRecordingVideo}');
      debugPrint('isTakingPicture: ${_controller!.value.isTakingPicture}');

      // Ensure the camera preview is active
      if (_controller!.value.isPreviewPaused) {
        debugPrint('Resuming camera preview...');
        await _controller!.resumePreview();
      }

      // Attempt to take the picture
      debugPrint('Attempting to take picture...');
      final image = await _controller!.takePicture();
      debugPrint('Picture taken successfully: ${image.path}');

      // Convert image to base64
      final bytes = await File(image.path).readAsBytes();
      final base64Image = base64Encode(bytes);

      // Send to API
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        setState(() {
          _status =
              result['drowsy_detected']
                  ? 'Drowsy Detected (Confidence: ${(result['confidence'] * 100).toStringAsFixed(2)}%)'
                  : 'No Drowsiness Detected';
          _processedImage = result['processed_image'] ?? '';
        });
      } else {
        setState(() {
          _status = 'API Error: ${response.statusCode}';
        });
      }
    } catch (e) {
      if (e.toString().contains('Unsupported operation: _Namespace')) {
        setState(() {
          _status =
              'Error: Camera operation failed (Unsupported operation: _Namespace). Try restarting the app or using a different device.';
        });
      } else {
        setState(() {
          _status = 'Error during detection: $e';
        });
      }
    } finally {
      setState(() {
        _isDetecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drowsiness Detection'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<void>(
                future: _initializeControllerFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    if (_controller == null ||
                        !_controller!.value.isInitialized) {
                      return const Center(
                        child: Text(
                          'Camera not initialized',
                          style: TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return CameraPreview(_controller!);
                  }
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 16.0,
              ),
              child: Text(
                _status,
                style: TextStyle(
                  fontSize: 16,
                  color: _status.contains('Error') ? Colors.red : Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (_processedImage.isNotEmpty)
              Container(
                height: 200,
                margin: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Image.memory(
                  base64Decode(_processedImage),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Text(
                        'Error loading processed image',
                        style: TextStyle(color: Colors.red),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: _isDetecting ? null : _detectDrowsiness,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32.0,
                    vertical: 16.0,
                  ),
                ),
                child: const Text(
                  'Detect Drowsiness',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
