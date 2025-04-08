import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

class CameraView extends StatefulWidget {
  const CameraView({
    super.key,
    required this.onImage,
  });

  final Function(InputImage inputImage) onImage;

  @override
  State<CameraView> createState() => _CameraViewState();

  static final GlobalKey<_CameraViewState> cameraKey = GlobalKey();
}

class _CameraViewState extends State<CameraView> {
  //สำหรับเก็บจำนวนกล้องทั้งหมดที่มี
  List<CameraDescription> _cameras = [];

//ตัวควบคุมกล้อง
  CameraController? _cameraController;

//เก็บ index ของกล้องที่ต้องการ
  int _cameraIndex = -1;

  Size? cameraSize;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  void _initialize() async {
    _cameras = await availableCameras();

    for (var i = 0; i < _cameras.length; i++) {
      if (_cameras[i].lensDirection == CameraLensDirection.front) {
        _cameraIndex = i;
        break;
      }
    }

    if (_cameraIndex != -1) {
      await _liveFeed();
    }
  }

  Future _liveFeed() async {
    //ควบคุมกล้องตรงนี้
    _cameraController = CameraController(
      _cameras[_cameraIndex],
      //ตั้งค่า resolution ไว้ที่ high เพื่อให้คุณภาพรูปที่ดี แต่ในบางเครื่องอาจจะไม่รองรับ
      ResolutionPreset.high,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await _cameraController?.initialize().then((_) async {
      if (!mounted) {
        return;
      }
      if (_cameraController != null) {
        //ทำการ process image จากกล้องออกมา
        _cameraController!.startImageStream(_processCameraImage);
      }
      setState(() {});
    });
    print('ENTRY  ------------------ ${_cameraController?.value.previewSize}');
    cameraSize = _cameraController?.value.previewSize;
  }

  @override
  void dispose() {
    super.dispose();
    _stopFeed();
  }

  void _stopFeed() async {
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();
    _cameraController = null;
  }

  void _processCameraImage(CameraImage image) {
    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return;
    //นำรูปที่ได้มาประมวลผล
    widget.onImage(inputImage);
  }

  Future<Uint8List?> _resizeImage(XFile file) async {
    // อ่านรูปจากไฟล์
    final bytes = await file.readAsBytes();
    img.Image? image = img.decodeImage(bytes);

    if (image == null) return null; // ถ้าอ่านไม่ได้ให้คืนไฟล์เดิม

    int width = 540;

    // ปรับขนาดรูปภาพ
    img.Image resized = img.copyResize(
      image,
      width: width,
      height: ((image.height * width) / image.width).round(),
    );

    // แปลงกลับเป็น Uint8List
    final resizedBytes = img.encodeJpg(resized, quality: 100);

    return resizedBytes;
  }

  Future capturePhoto() async {
    log('_cameraController ${_cameraController == null || !_cameraController!.value.isInitialized}');
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final image = await _cameraController!.takePicture();

      Uint8List? uint8ListImage = await _resizeImage(image);

      if (uint8ListImage == null) return;

      log("ถ่ายภาพสำเร็จ");

      //จะทำการ return ค่า byte กลับไป
      var base64String = base64Encode(uint8ListImage);

      return base64String;
    } catch (e) {
      log("ไม่สามารถบันทึกภาพได้: $e");
      return null;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_cameraController == null) return null;
    // ดึงรูปที่นี่
    Size size = Size(image.width.toDouble(), image.height.toDouble());
    //rotation
    InputImageRotation? rotation;
    int bytesPerRow = 0;
    Uint8List? bytes;

    final camera = _cameras[_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;

    final _orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    if (Platform.isIOS) {
      //โดยภายใน iOS ไม่ได้มีการนำค่าไปใช้ เพียงแต่ระบุเพื่อให้ใช้ function ได้
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      //เนื่องจาก lib camera รูปที่ได้จากกล้องจะต้องทำการหมุน เพื่อให้ได้องศาที่เหมาะสม
      var rotationCompensation =
          _orientations[_cameraController!.value.deviceOrientation];
      if (rotationCompensation == null) return null;

      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    var format = InputImageFormatValue.fromRawValue(image.format.raw);

    if (Platform.isIOS) {
      if (image.planes.length != 1) {
        return null;
      }
      final plane = image.planes.first;
      bytes = plane.bytes;
      bytesPerRow = plane.bytesPerRow;
    } else if (Platform.isAndroid) {
      if (format == InputImageFormat.nv21) {
        if (image.planes.length != 1) {
          return null;
        }
        final plane = image.planes.first;
        bytes = plane.bytes;
      } else {
        //เรียกใช้ตรงนี้
        bytes = convertYUV420ToNV21(image);
        format = InputImageFormat.nv21;
      }
    }

    if (bytes == null || rotation == null || format == null) return null;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: size,
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  Uint8List convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = (width ~/ 2) * (height ~/ 2) * 2;

    Uint8List nv21 = Uint8List(ySize + uvSize);
    Uint8List yBuffer = image.planes[0].bytes;
    Uint8List uBuffer = image.planes[1].bytes;
    Uint8List vBuffer = image.planes[2].bytes;

    // Copy Y
    nv21.setRange(0, ySize, yBuffer);

    // Interleave U & V (UV)
    int uvIndex = ySize;
    for (int i = 0; i < uBuffer.length && i < vBuffer.length; i++) {
      if (uvIndex + 1 < nv21.length) {
        nv21[uvIndex++] = vBuffer[i]; // V
        nv21[uvIndex++] = uBuffer[i]; // U
      }
    }

    return nv21;
  }

  @override
  Widget build(BuildContext context) {
    if (_cameras.isEmpty || _cameraController == null) return Container();
    return Scaffold(
      body: Center(
        //เนื่องด้วย lib camera ต้องครอบการ flip กล้อง
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationY(Platform.isAndroid ? math.pi : 0),
          child: CameraPreview(_cameraController!),
        ),
      ),
    );
  }
}
