import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:fvs_mobile/apiService.dart';
import 'package:fvs_mobile/cemaraView.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

Color boarderColor = Colors.red; //ตั้งสีเริ่มต้นของ frame

class MainScreen extends StatefulWidget {
  MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true, //เป็นการจับกรอบหน้า และขนาดตา รอยยิ้ม
      enableLandmarks: true, //เป็นการจับตำแหน่ง ตา จมูก ปาก
    ),
  );
  var _imageKey = GlobalKey();
  String? _text;
  bool _isBusy = false;
  bool _canProcess = true;
  // ตัวแปรเก็บ Stopwatch
  Stopwatch _stopwatch = Stopwatch();
  Uint8List? _file;
  bool _isCaptured = false;
  String? _base64Image;

  // ตัวแปรเก็บเวลา (ในหน่วยวินาที)
  String get elapsedTime => _stopwatch.elapsed.inSeconds.toString();

  @override
  void dispose() {
    _canProcess = false;
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;

    if (mounted) {
      setState(() {
        _isBusy = true;
      });
    }

    final faces = await _faceDetector.processImage(inputImage);

    if (inputImage.metadata?.size != null &&
        inputImage.metadata?.rotation != null) {
      var cameraSize = inputImage.metadata!.size;
      if (faces.isNotEmpty) {
        if (faces.length == 1) {
          Rect? rectFrame;
          var getGlobalPosition = getFrameGlobalPosition(_imageKey);
          if (getGlobalPosition != null) {
            rectFrame = getGlobalPosition;
          }
          if (rectFrame == null) return;

          Rect rectFace = convertFaceBoundingBox(
            faces.first.boundingBox,
            cameraSize,
            MediaQuery.of(context).size,
          );
          if (_isFaceInFrame(rectFace, rectFrame)) {
            _text = 'พบใบหน้าแล้ว';
            boarderColor = Colors.yellowAccent;
            if (_isFaceCentered(rectFace, rectFrame)) {
              // เปลี่ยนสีและ _text เมื่อใบหน้าอยู่ตรงกลางกรอบ
              _text = 'นิ่งๆ';
              boarderColor = Colors.green;
              checkFrameColor(true);
            } else if (_isFaceCloseupFrame(rectFace, rectFrame)) {
              _text = 'ใกล้เกินไป';
              boarderColor = Colors.orangeAccent;
              checkFrameColor(false);
            }
          } else {
            _text = null;
            boarderColor = Colors.red;
            checkFrameColor(false);
          }
        } else {
          _text = 'ตรวจพบหลายใบหน้า';
          boarderColor = Colors.blueAccent;
        }
      }
    } else {
      _text = '';
      boarderColor = Colors.red;
    }
    if (mounted) {
      setState(() {
        _isBusy = false;
      });
    }
  }

  void checkFrameColor(bool isFrameGreen) async {
    if (isFrameGreen) {
      if (!_stopwatch.isRunning) {
        // เริ่มจับเวลาเมื่อกรอบเป็นสีเขียว
        _stopwatch.start();
        log("เริ่มจับเวลาแล้ว");
      }
      if (_stopwatch.isRunning) {
        int second = int.parse(elapsedTime);
        if (second > 0) _text = second.toString();
        if (second == 3) {
          log('_isCaptured $_isCaptured');
          if (_isCaptured) return;

          log('_isCaptured Entry $_isCaptured');

          _isCaptured = true;
          //capture here
          var result = await CameraView.cameraKey.currentState?.capturePhoto();
          if (result is String) {
            if (mounted) {
              setState(() {
                _base64Image = result;
              });
            }
          }
          await Future.delayed(const Duration(seconds: 3), () {
            _isCaptured = false;
          });
        } else if (second > 3) {
          _text = '';
          //ถ้าจับเวลามากกว่า 3 วินาทีให้เริ่มต้นนับใหม่
          _stopwatch.reset();
        }
      }
    } else {
      //จะทำการหยุดการจับเวลาเมื่อกรอบเปลี่ยนสี
      if (_stopwatch.isRunning) {
        _text = '';
        // หยุดจับเวลาเมื่อกรอบกลับไปเป็นสีอื่น
        _stopwatch.stop();
        //เพิ่มการ reset หาก _stopwatch หยุดการทำงาน เพื่อจับเวลาใหม่
        _stopwatch.reset();
        log("หยุดจับเวลา: เวลา = $elapsedTime วินาที");
      }
    }
  }

  Rect? getFrameGlobalPosition(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    final translation = renderObject?.getTransformTo(null).getTranslation();
    if (translation != null && renderObject?.paintBounds != null) {
      final offset = Offset(translation.x, translation.y);
      return renderObject!.paintBounds.shift(offset);
    }
    return null;
  }

  bool _isFaceInFrame(Rect face, Rect frame) {
    double faceWidth = face.width;
    double faceHeight = face.height;

    double marginPositionX = faceWidth * 0.05;
    double marginPositionY = faceHeight * 0.2;

    var faceTopLeft = Offset(
      face.topLeft.dx + marginPositionX,
      face.topLeft.dy + marginPositionY,
    );
    var faceBottomRight = Offset(
      face.bottomRight.dx - marginPositionX,
      face.bottomRight.dy - marginPositionY,
    );

    // เป็นการคำนวณว่าตำแหน่งของใบหน้าบนซ้ายและล่างขวาอยู่ภายใน frame หรือไม่
    return frame.contains(faceTopLeft) && frame.contains(faceBottomRight);
  }

  bool _isFaceCloseupFrame(Rect face, Rect frame) {
    double faceWidth = face.width;
    double faceHeight = face.height;
    double frameWidth = frame.width;
    double frameHeight = frame.height;

    // คำนวณว่าใบหน้าใกล้กับ frame ไหม โดยคำนวณจากความกว้างและยาวของใบหน้า ต้องไม่เกินขอบ frame
    return faceWidth >= frameWidth * 0.95 || faceHeight >= frameHeight;
  }

  Rect convertFaceBoundingBox(Rect faceBox, Size cameraSize, Size screenSize) {
    double scaleX = screenSize.width / cameraSize.height;
    double scaleY = screenSize.height / cameraSize.width;

    return Rect.fromLTRB(
      faceBox.left * scaleX,
      faceBox.top * scaleY,
      faceBox.right * scaleX,
      faceBox.bottom * scaleY,
    );
  }

  bool _isFaceCentered(Rect face, Rect frame) {
    double frameWidth = frame.width;
    double frameHeight = frame.height;

    // อนุญาตให้คลาดเคลื่อน ±5% ของกรอบ
    double marginPositionX = frameWidth * 0.05;
    double marginPositionY = frameHeight * 0.2;

    double faceCenterX = face.center.dx;
    double faceCenterY = face.center.dy;

    double frameCenterX = frame.center.dx;
    double frameCenterY = frame.center.dy;

    double faceWidth = face.width;
    double faceHeight = face.height;

    //กำหนดให้ตรงกลางของใบหน้าอยู่ระว่างตรงกลาง +- กับค่าความคลาดเคลื่อนของกรอบที่กำหนด
    return (faceCenterX >= frameCenterX - marginPositionX &&
            faceCenterX <= frameCenterX + marginPositionX) &&
        (faceCenterY >= frameCenterY - marginPositionY &&
            faceCenterY <= frameCenterY + marginPositionY) &&
        //ขนาดความกว้างของใบหน้าต้องมากกว่าความกว้างของ frame * 0.6
        //นั่นหมายความว่าใบหน้าจะไม่อยู่ไกลจาก frame มากเกินไป
        (faceWidth >= frameWidth * 0.6) &&
        //ขนาดความกว้างของใบหน้าต้องไม่เกินความกว้างของ frame
        (faceWidth <= frameWidth &&
            //ขนาดความสูงของใบหน้าต้องไม่เกินความสูงของ frame
            faceHeight <= frameHeight);
  }

  Future _showDialog(String msg) async => await showDialog(
        context: context,
        builder: (BuildContext context) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(msg),
                const SizedBox(height: 15),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          if (_base64Image != null) ...[
            //ทำการหมุนภาพเพื่อเนื่องจากเป็นภาพที่ได้จากกล้องหน้า
            Center(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(math.pi),
                child: Image.memory(
                  base64Decode(_base64Image!),
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            //ปุ่มสำหรับทำการ detector อีกครั้ง
            Positioned(
              bottom: 50,
              left: 50,
              child: GestureDetector(
                onTap: () {
                  //ทำการ reset รูป และตัวจับเวลา
                  _isBusy = false;
                  _text = null;
                  boarderColor = Colors.red;
                  _base64Image = null;
                  _stopwatch.reset();
                  setState(() {});
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsetsDirectional.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black26.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.refresh,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 50,
              right: 50,
              child: GestureDetector(
                onTap: () async {
                  String msg = '';
                  try {
                    await ApiService().personalVerify(
                      imageBase64: _base64Image ?? '',
                      pid: '<YOUR_PID>',
                    );
                    msg = 'Successful';
                  } catch (e) {
                    msg = e.toString();
                  }
                  await _showDialog(msg);
                  _isBusy = false;
                  _text = null;
                  boarderColor = Colors.red;
                  _base64Image = null;
                  _stopwatch.reset();
                  setState(() {});
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsetsDirectional.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black26.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ] else ...[
            CameraView(
              //เพิ่ม function การประมวลผลภาพ
              key: CameraView.cameraKey,
              onImage: _processImage,
            ),
            CustomPaint(
              size: Size(
                MediaQuery.of(context).size.width / 1.5,
                MediaQuery.of(context).size.width / 1.5,
              ),
              key: _imageKey,
              painter: CirclePainter(),
            ),
            if (_text != null && _text != '')
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _text ?? '',
                  style: TextStyle(fontSize: 20),
                ),
              ),
          ]
        ],
      ),
    );
  }
}

class CirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = boarderColor // สีของขอบวงกลม
      ..style = PaintingStyle.stroke // ใช้ stroke เพื่อให้มีแต่ขอบ
      ..strokeWidth = 4; // ความหนาของขอบ

    final double radius = size.width / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
