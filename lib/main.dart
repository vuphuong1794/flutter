import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check if running on web
  if (kIsWeb) {
    runApp(const MyApp(camera: null));
  } else {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw Exception('No cameras available on this device');
    }
    final firstCamera = cameras.first;
    runApp(MyApp(camera: firstCamera));
  }
}

class MyApp extends StatelessWidget {
  final CameraDescription? camera;

  const MyApp({super.key, required this.camera});

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
  final CameraDescription? camera;

  const DrowsinessDetector({super.key, required this.camera});

  @override
  State<DrowsinessDetector> createState() => _DrowsinessDetectorState();
}

class _DrowsinessDetectorState extends State<DrowsinessDetector> {
  CameraController? _controller;
  late Future<void> _initializeControllerFuture;
  String _status = 'Initializing...';
  String _processedImage = '';
  bool _isDetecting = false;
  Uint8List? _webImage; // For storing image data on web

  final String apiUrl = 'http://192.168.1.9:5000/api/detect_drowsiness';

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      _initializeControllerFuture = Future.value();
      setState(() {
        _status = 'Web platform detected. Using alternative camera access.';
      });
    } else {
      _initializeControllerFuture = Future.value();
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.camera == null) return;

    try {
      _controller = CameraController(
        widget.camera!,
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

  Future<Uint8List?> _getImageFromCamera() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      if (kIsWeb) {
        // For web, read the image as bytes
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _webImage = bytes;
          _status = 'Image captured';
        });
        return bytes;
      } else {
        // For mobile, read as bytes
        final bytes = await pickedFile.readAsBytes();
        return bytes;
      }
    }
    return null;
  }

  Future<void> _detectDrowsiness() async {
    if (_isDetecting) {
      setState(() {
        _status = 'Detection already in progress';
      });
      return;
    }

    setState(() {
      _isDetecting = true;
      _status = 'Detecting...';
      _processedImage = '';
    });

    try {
      Uint8List? imageBytes;

      if (kIsWeb) {
        // Web platform - use ImagePicker
        imageBytes = await _getImageFromCamera();
        if (imageBytes == null) {
          setState(() {
            _status = 'No image captured';
            _isDetecting = false;
          });
          return;
        }
      } else {
        // Mobile platform - use Camera plugin
        if (_controller == null || !_controller!.value.isInitialized) {
          setState(() {
            _status = 'Error: Camera is not initialized';
            _isDetecting = false;
          });
          return;
        }

        await _initializeControllerFuture;

        // Log camera state for debugging
        debugPrint('Camera state before taking picture:');
        debugPrint('isInitialized: ${_controller!.value.isInitialized}');
        debugPrint('isPreviewPaused: ${_controller!.value.isPreviewPaused}');
        debugPrint('isRecordingVideo: ${_controller!.value.isRecordingVideo}');
        debugPrint('isTakingPicture: ${_controller!.value.isTakingPicture}');

        // Attempt to take the picture
        debugPrint('Attempting to take picture...');
        final image = await _controller!.takePicture();
        debugPrint('Picture taken successfully: ${image.path}');

        // Convert image to bytes
        imageBytes = await image.readAsBytes();
      }

      if (imageBytes != null) {
        // Convert to base64 and send to API
        final base64Image = base64Encode(imageBytes);

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
      }
    } catch (e) {
      setState(() {
        _status = 'Error during detection: $e';
      });
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
              child: kIsWeb ? _buildWebCameraView() : _buildNativeCameraView(),
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

  Widget _buildWebCameraView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_webImage != null)
            SizedBox(
              height: 300,
              child: Image.memory(_webImage!, fit: BoxFit.contain),
            )
          else
            const Icon(Icons.camera_alt, size: 100, color: Colors.grey),
          const SizedBox(height: 20),
          const Text(
            'Click "Detect Drowsiness" to use the camera',
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildNativeCameraView() {
    return FutureBuilder<void>(
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
          if (_controller == null || !_controller!.value.isInitialized) {
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
    );
  }
}
