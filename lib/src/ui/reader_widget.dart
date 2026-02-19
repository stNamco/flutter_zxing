import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../flutter_zxing.dart';
import '../../flutter_zxing.dart' as zxing;
import '../utils/image_converter.dart';
import 'scan_mode_dropdown.dart';

/// Widget to scan a code from the camera stream
class ReaderWidget extends StatefulWidget {
  const ReaderWidget({
    super.key,
    this.onScan,
    this.onScanFailure,
    this.onMultiScan,
    this.onMultiScanFailure,
    this.onControllerCreated,
    this.onMultiScanModeChanged,
    this.isMultiScan = false,
    this.multiScanModeAlignment = Alignment.bottomRight,
    this.multiScanModePadding = const EdgeInsets.all(10),
    this.codeFormat = Format.any,
    this.tryHarder = false,
    this.tryInverted = false,
    this.tryRotate = true,
    this.tryDownscale = false,
    this.maxNumberOfSymbols = 10,
    this.showScannerOverlay = true,
    this.scannerOverlay,
    this.actionButtonsAlignment = Alignment.bottomLeft,
    this.actionButtonsPadding = const EdgeInsets.all(10),
    this.showFlashlight = true,
    this.showToggleCamera = true,
    this.showGallery = true,
    this.flashOnIcon = const Icon(Icons.flash_on),
    this.flashOffIcon = const Icon(Icons.flash_off),
    this.flashAlwaysIcon = const Icon(Icons.flash_on),
    this.flashAutoIcon = const Icon(Icons.flash_auto),
    this.galleryIcon = const Icon(Icons.photo_library),
    this.toggleCameraIcon = const Icon(Icons.switch_camera),
    this.actionButtonsBackgroundColor = Colors.black,
    this.actionButtonsBackgroundBorderRadius,
    this.allowPinchZoom = true,
    this.initialZoom = 1.0,
    this.scanDelay = const Duration(milliseconds: 1000),
    this.scanDelaySuccess = const Duration(milliseconds: 1000),
    this.cropPercent = 0.5, // 50% of the screen
    this.horizontalCropOffset = 0.0,
    this.verticalCropOffset = 0.0,
    this.resolution = ResolutionPreset.high,
    this.lensDirection = CameraLensDirection.back,
    this.loading =
        const DecoratedBox(decoration: BoxDecoration(color: Colors.black)),
    this.onActionSecondButton,
    this.actionSecondButtonIcon,
    this.actionSecondButtonIconBackgroundColor,
    this.debugSaveFrame = false,
    this.onSharpnessChanged,
  });

  /// Called when a code is detected
  final Function(Code)? onScan;

  /// Called when a code is not detected
  final Function(Code)? onScanFailure;

  /// Called when a code is detected
  final Function(Codes)? onMultiScan;

  /// Called when a code is not detected
  final Function(Codes)? onMultiScanFailure;

  /// Called when the camera controller is created
  final Function(CameraController? controller, Exception? error)?
      onControllerCreated;

  /// Called when the multi scan mode is changed
  /// When set to null, the multi scan mode button will not be displayed
  final Function(bool)? onMultiScanModeChanged;

  /// Allow multiple scans
  final bool isMultiScan;

  /// Alignment for multi scan mode button
  final AlignmentGeometry multiScanModeAlignment;

  /// Padding for multi scan mode button
  final EdgeInsetsGeometry multiScanModePadding;

  /// Code format to scan
  final int codeFormat;

  /// Try harder to detect a code
  final bool tryHarder;

  /// Try to detect inverted code
  final bool tryInverted;

  /// Try to rotate the image
  final bool tryRotate;

  /// Try to downscale the image
  final bool tryDownscale;

  /// Maximum number of barcodes to detect
  final int maxNumberOfSymbols;

  /// Show cropping rect
  final bool showScannerOverlay;

  /// Custom scanner overlay
  final ShapeBorder? scannerOverlay;

  /// Align for action buttons
  final AlignmentGeometry actionButtonsAlignment;

  /// Padding for action buttons
  final EdgeInsetsGeometry actionButtonsPadding;

  /// Show flashlight button
  final bool showFlashlight;

  /// Show toggle camera
  final bool showGallery;

  /// Show toggle camera
  final bool showToggleCamera;

  /// Custom flash_on icon
  final Widget flashOnIcon;

  /// Custom flash_off icon
  final Widget flashOffIcon;

  /// Custom flash_always icon
  final Widget flashAlwaysIcon;

  /// Custom flash_auto icon
  final Widget flashAutoIcon;

  /// Custom gallery icon
  final Widget galleryIcon;

  /// Custom camera toggle icon
  final Widget toggleCameraIcon;

  /// Custom background color for action buttons
  final Color actionButtonsBackgroundColor;

  /// Custom background border radius for action buttons
  final BorderRadius? actionButtonsBackgroundBorderRadius;

  /// Allow pinch zoom
  final bool allowPinchZoom;

  /// Initial zoom level (1.0 = no zoom). Will be clamped to device's min/max range.
  final double initialZoom;

  /// Delay between scans when no code is detected
  final Duration scanDelay;

  /// Crop percent of the screen, will be ignored if isMultiScan is true
  final double cropPercent;

  /// Move the crop rect vertically, using a value from -1 (top) to 1 (bottom); ignored if [isMultiScan] is true
  final double verticalCropOffset;

  /// Move the crop rect horizontally, using a value from -1 (left) to 1 (right); ignored if [isMultiScan] is true
  final double horizontalCropOffset;

  /// Camera resolution
  final ResolutionPreset resolution;

  /// Camera lens direction
  final CameraLensDirection lensDirection;

  /// Delay between scans when a code is detected, will be ignored if isMultiScan is true
  final Duration scanDelaySuccess;

  /// Loading widget while camera is initializing. Default is a black screen
  final Widget loading;

  /// Callback for second action button
  final Function()? onActionSecondButton;

  /// Second action icon to be displayed on the right side of the action buttons
  final Widget? actionSecondButtonIcon;

  /// Background color for the second action icon
  final Color? actionSecondButtonIconBackgroundColor;

  /// Save debug frames (cropped grayscale PNG) to temp directory on scan failure
  final bool debugSaveFrame;

  /// Called on each frame with sharpness info.
  /// [sharpness] is the Laplacian variance, [isSharp] indicates if it exceeds the threshold.
  final void Function(double sharpness, bool isSharp)? onSharpnessChanged;

  @override
  State<ReaderWidget> createState() => _ReaderWidgetState();
}

class _ReaderWidgetState extends State<ReaderWidget>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  List<CameraDescription> cameras = <CameraDescription>[];
  CameraDescription? selectedCamera;
  CameraController? controller;

  // true when code detecting is ongoing
  bool _isProcessing = false;
  bool _isCameraOn = false;
  bool _isFlashAvailable = true;
  bool _isMultiScan = false;
  bool _isInitializing = false;
  String _controllerVersion = '';
  Completer<void>? _initializationCompleter;

  double _zoom = 1.0;
  double _scaleFactor = 1.0;
  double _maxZoomLevel = 1.0;
  double _minZoomLevel = 1.0;

  Codes results = Codes();

  // デバッグフレーム保存用
  DateTime _lastDebugSave = DateTime(2000);
  int _debugFrameCount = 0;

  // 解像度ログを1回だけ出力するためのフラグ
  bool _hasLoggedResolution = false;

  // ベストフレーム選択用：シャープネスログを初回のみ出力
  bool _hasLoggedSharpness = false;

  bool isAndroid() => Theme.of(context).platform == TargetPlatform.android;

  /// Yプレーン中央領域のLaplacian分散でシャープネスを計算
  /// 値が大きいほどシャープ（エッジが明瞭）
  double _calculateSharpness(CameraImage image) {
    final Plane yPlane = image.planes.first;
    final Uint8List bytes = yPlane.bytes;
    final int width = image.width;
    final int height = image.height;
    final int bytesPerRow = yPlane.bytesPerRow;

    // 中央50%の領域のみ評価（QRコードが映っている可能性が高い領域）
    final int regionX = width ~/ 4;
    final int regionY = height ~/ 4;
    final int regionW = width ~/ 2;
    final int regionH = height ~/ 2;

    // 4ピクセルおきにサンプリング（高速化）
    const int step = 4;

    double sum = 0;
    double sumSq = 0;
    int count = 0;

    for (int y = regionY; y < regionY + regionH; y += step) {
      if (y <= 0 || y >= height - 1) continue;
      for (int x = regionX; x < regionX + regionW; x += step) {
        if (x <= 0 || x >= width - 1) continue;
        // Laplacian: 4*center - up - down - left - right
        final int center = bytes[y * bytesPerRow + x];
        final int up = bytes[(y - 1) * bytesPerRow + x];
        final int down = bytes[(y + 1) * bytesPerRow + x];
        final int left = bytes[y * bytesPerRow + (x - 1)];
        final int right = bytes[y * bytesPerRow + (x + 1)];
        final double laplacian =
            (4 * center - up - down - left - right).toDouble();
        sum += laplacian;
        sumSq += laplacian * laplacian;
        count++;
      }
    }

    if (count == 0) return 0;
    final double mean = sum / count;
    return (sumSq / count) - (mean * mean);
  }

  /// デバッグ用: クロップ済みグレースケール画像をPNGとして保存
  void _saveDebugFrame(
      CameraImage image, int cropLeft, int cropTop, int cropSize) {
    try {
      final Plane yPlane = image.planes.first;
      final int bytesPerRow = yPlane.bytesPerRow;
      final int w = cropSize > 0 ? cropSize : image.width;
      final int h = cropSize > 0 ? cropSize : image.height;
      final int left = cropSize > 0 ? cropLeft : 0;
      final int top = cropSize > 0 ? cropTop : 0;

      // Y planeからクロップ領域を抽出
      final Uint8List cropped = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        final int srcOffset = (top + y) * bytesPerRow + left;
        cropped.setRange(y * w, y * w + w, yPlane.bytes, srcOffset);
      }

      // PNGに変換して保存
      final Uint8List pngBytes = pngFromBytes(cropped, w, h);

      final Directory dir =
          Directory('${Directory.systemTemp.path}/debug_frames');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _debugFrameCount++;
      final String name =
          'frame_${_debugFrameCount.toString().padLeft(4, '0')}.png';
      final File file = File('${dir.path}/$name');
      file.writeAsBytesSync(pngBytes);
      debugPrint(
        'ReaderWidget: debug frame saved: ${file.path} '
        '(${w}x${h}, crop=$cropLeft,$cropTop)',
      );
    } catch (e) {
      debugPrint('ReaderWidget: failed to save debug frame: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isMultiScan = widget.isMultiScan;
    initStateAsync();
  }

  Future<void> initStateAsync() async {
    try {
      await zx.startCameraProcessing();
      final List<CameraDescription> cameras = await availableCameras();

      if (!mounted) {
        return;
      }

      this.cameras = cameras;
      if (cameras.isNotEmpty) {
        selectedCamera = cameras.firstWhere(
          (CameraDescription camera) =>
              camera.lensDirection == widget.lensDirection,
          orElse: () => cameras.first,
        );
        await onNewCameraSelected(selectedCamera);
      }
    } catch (e) {
      debugPrint('initStateAsync error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        if (cameras.isNotEmpty && !_isCameraOn) {
          onNewCameraSelected(selectedCamera ?? cameras.first);
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _stopCamera();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    // Cancel any ongoing initialization
    if (_initializationCompleter != null &&
        !_initializationCompleter!.isCompleted) {
      _initializationCompleter!.complete();
    }

    _stopCamera();
    _disposeController();
    zx.stopCameraProcessing();
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  void rebuildOnMount() {
    if (mounted) {
      _isCameraOn = true;
    }
  }

  Future<void> _disposeController() async {
    final CameraController? oldController = controller;

    if (oldController != null) {
      // Immediately nullify controller and invalidate version
      controller = null;
      _isCameraOn = false;
      _isProcessing = false;
      _controllerVersion = 'disposed_${DateTime.now().millisecondsSinceEpoch}';

      oldController.removeListener(rebuildOnMount);

      // Aggressively stop image stream
      if (oldController.value.isStreamingImages) {
        for (int i = 0; i < 5; i++) {
          try {
            await oldController.stopImageStream();
            break;
          } catch (e) {
            if (i < 2) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }
        }
      }

      try {
        await oldController.dispose();
      } catch (e) {
        debugPrint('_disposeController dispose error: $e');
      }
    }
  }

  void _stopCamera() {
    if ((controller?.value.isStreamingImages ?? false) == false) {
      try {
        controller?.stopImageStream();
      } catch (e) {
        debugPrint('stopImageStream error: $e');
      }
    }
    _isCameraOn = false;
    _isProcessing = false;
  }

  Future<void> onNewCameraSelected(CameraDescription? cameraDescription) async {
    if (cameraDescription == null) {
      return;
    }

    // Cancel any ongoing initialization
    if (_initializationCompleter != null &&
        !_initializationCompleter!.isCompleted) {
      _initializationCompleter!.complete();
    }

    if (_isInitializing) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (_isInitializing) {
        return;
      }
    }

    _isInitializing = true;
    _initializationCompleter = Completer<void>();

    await _disposeController();

    // Reset processing state and create new version
    _isProcessing = false;
    _hasLoggedResolution = false;
    _hasLoggedSharpness = false;
    _controllerVersion = DateTime.now().millisecondsSinceEpoch.toString();
    final String currentVersion = _controllerVersion;

    // Small delay to ensure complete disposal
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final CameraController cameraController = CameraController(
      cameraDescription,
      widget.resolution,
      enableAudio: false,
    );
    controller = cameraController;

    try {
      await cameraController.initialize();
      if (!mounted) {
        return;
      }

      widget.onControllerCreated?.call(controller, null);
      cameraController.addListener(rebuildOnMount);

      if (cameraController.value.isInitialized &&
          !cameraController.value.isStreamingImages) {
        try {
          await cameraController.startImageStream(
              (CameraImage image) => processImageStream(image, currentVersion));

          // Verify stream is actually running
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!cameraController.value.isStreamingImages) {
            await cameraController.startImageStream((CameraImage image) =>
                processImageStream(image, currentVersion));
          }
        } catch (e) {
          debugPrint('onNewCameraSelected: failed to start image stream: $e');
        }
      }

      _maxZoomLevel = await cameraController.getMaxZoomLevel();
      _minZoomLevel = await cameraController.getMinZoomLevel();

      // 初期ズームレベルを設定
      if (widget.initialZoom > _minZoomLevel) {
        _scaleFactor = widget.initialZoom.clamp(_minZoomLevel, _maxZoomLevel);
        _zoom = _scaleFactor;
        await cameraController.setZoomLevel(_scaleFactor);
        debugPrint(
          'ReaderWidget: initialZoom=${widget.initialZoom}, '
          'applied=${_scaleFactor.toStringAsFixed(1)}, '
          'range=[$_minZoomLevel, $_maxZoomLevel]',
        );
      }

      // バーコード/QRコードスキャン向けに連続オートフォーカスを有効化
      // フォーカス・露出ポイントを中央に設定し、QRコードに最適化
      try {
        await cameraController.setFocusMode(FocusMode.auto);
        await cameraController.setFocusPoint(const Offset(0.5, 0.5));
      } catch (e) {
        debugPrint('onNewCameraSelected: failed to set focus: $e');
      }
      try {
        await cameraController.setExposurePoint(const Offset(0.5, 0.5));
      } catch (e) {
        debugPrint('onNewCameraSelected: failed to set exposure point: $e');
      }

      try {
        await cameraController.setFlashMode(FlashMode.off);
        if (!_isFlashAvailable && mounted) {
          setState(() => _isFlashAvailable = true);
        }
      } catch (e) {
        if (e is CameraException && e.code == 'setFlashModeFailed') {
          if (mounted) {
            setState(() {
              _isFlashAvailable = false;
            });
          }
        }
      }

      if (mounted) {
        setState(() => _isCameraOn = true);
      }

      // Force restart stream after initialization to ensure it works
      if (cameraController.value.isStreamingImages) {
        try {
          await cameraController.stopImageStream();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await cameraController.startImageStream(
              (CameraImage image) => processImageStream(image, currentVersion));
        } catch (e) {
          debugPrint('onNewCameraSelected: stream restart failed: $e');
        }
      }
    } catch (e) {
      if (e is CameraException && e.code == 'setFlashModeFailed') {
        setState(() {
          _isFlashAvailable = false;
        });
      }
      widget.onControllerCreated
          ?.call(null, e is Exception ? e : Exception(e.toString()));
    } finally {
      _isInitializing = false;
      if (_initializationCompleter != null &&
          !_initializationCompleter!.isCompleted) {
        _initializationCompleter!.complete();
      }
      _initializationCompleter = null;
    }
  }

  Future<void> processImageStream(CameraImage image, String version) async {
    // Early exit if version doesn't match or widget is disposed
    if (version != _controllerVersion ||
        !mounted ||
        _isInitializing ||
        controller == null ||
        version.startsWith('disposed_') ||
        _initializationCompleter != null) {
      return;
    }

    if (!_isProcessing) {
      _isProcessing = true;
      try {
        // 実際のカメラフレーム解像度をログ出力（初回のみ）
        if (!_hasLoggedResolution) {
          _hasLoggedResolution = true;
          debugPrint(
            'ReaderWidget: ImageAnalysis frame resolution: '
            '${image.width}x${image.height}, '
            'format: ${image.format.group}, '
            'planes: ${image.planes.length}, '
            'requested: ${widget.resolution}',
          );
        }

        // ベストフレーム選択: シャープネスが低いフレームをスキップ
        final double sharpness = _calculateSharpness(image);
        const double sharpnessThreshold = 200.0;
        final bool isSharp = sharpness >= sharpnessThreshold;
        debugPrint(
          'ReaderWidget: sharpness=${sharpness.toStringAsFixed(1)}, '
          'threshold=$sharpnessThreshold, '
          '${isSharp ? "PASS" : "SKIP"}',
        );
        widget.onSharpnessChanged?.call(sharpness, isSharp);
        if (!isSharp) {
          _isProcessing = false;
          return;
        }

        final double cropPercent = widget.isMultiScan ? 0 : widget.cropPercent;
        final int cropSize =
            (min(image.width, image.height) * cropPercent).round();

        final bool swapAxes = isAndroid() &&
            MediaQuery.of(context).orientation == Orientation.portrait;
        final double horizontalOffset =
            swapAxes ? widget.verticalCropOffset : widget.horizontalCropOffset;
        final double verticalOffset =
            swapAxes ? -widget.horizontalCropOffset : widget.verticalCropOffset;
        final int cropLeft = ((image.width - cropSize) ~/ 2 +
                (horizontalOffset * (image.width - cropSize) / 2))
            .round()
            .clamp(0, image.width - cropSize);
        final int cropTop = ((image.height - cropSize) ~/ 2 +
                (verticalOffset * (image.height - cropSize) / 2))
            .round()
            .clamp(0, image.height - cropSize);

        final DecodeParams params = DecodeParams(
          imageFormat: _imageFormat(image.format.group),
          format: widget.codeFormat,
          width: image.width,
          height: image.height,
          cropLeft: cropLeft,
          cropTop: cropTop,
          cropWidth: cropSize,
          cropHeight: cropSize,
          tryHarder: widget.tryHarder,
          tryRotate: widget.tryRotate,
          tryInverted: widget.tryInverted,
          tryDownscale: widget.tryDownscale,
          maxNumberOfSymbols: widget.maxNumberOfSymbols,
          isMultiScan: widget.isMultiScan,
        );
        if (widget.isMultiScan) {
          final Codes result = await zx.processCameraImageMulti(image, params);
          if (result.codes.isNotEmpty) {
            results = result;
            widget.onMultiScan?.call(result);
            if (!mounted) {
              return;
            }
            if (mounted) {
              setState(() {});
            }
            if (!widget.isMultiScan) {
              await Future<void>.delayed(widget.scanDelaySuccess);
            }
          } else {
            results = Codes();
            widget.onMultiScanFailure?.call(result);
          }
        } else {
          final Code result = await zx.processCameraImage(image, params);
          if (result.isValid) {
            results = Codes(codes: <Code>[result]);
            widget.onScan?.call(result);
            if (!mounted) {
              return;
            }
            if (mounted) {
              setState(() {});
            }
            await Future<void>.delayed(widget.scanDelaySuccess);
          } else {
            results = Codes();
            widget.onScanFailure?.call(result);

            // デバッグフレーム保存（3秒間隔）
            if (widget.debugSaveFrame) {
              final DateTime now = DateTime.now();
              if (now.difference(_lastDebugSave).inSeconds >= 3) {
                _lastDebugSave = now;
                _saveDebugFrame(image, cropLeft, cropTop, cropSize);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('processImageStream error: $e');
      } finally {
        // Check if still valid before delay
        if (version == _controllerVersion && mounted) {
          await Future<void>.delayed(widget.scanDelay);
        }
        _isProcessing = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isCameraReady = cameras.isNotEmpty &&
        _isCameraOn &&
        controller != null &&
        controller!.value.isInitialized;
    final Size size = MediaQuery.of(context).size;
    final double cameraMaxSize = max(size.width, size.height);
    final double cropSize = min(size.width, size.height) * widget.cropPercent;
    return Stack(
      children: <Widget>[
        if (!isCameraReady) widget.loading,
        if (isCameraReady)
          SizedBox(
            width: cameraMaxSize,
            height: cameraMaxSize,
            child: ClipRRect(
              child: OverflowBox(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: cameraMaxSize,
                    child: CameraPreview(
                      controller!,
                      child: widget.showScannerOverlay &&
                              results.codes.isNotEmpty &&
                              widget.cropPercent == 0
                          ? MultiResultOverlay(
                              results: results.codes,
                              onCodeTap: widget.onScan,
                              controller: controller,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (widget.showScannerOverlay &&
            widget.cropPercent != 0 &&
            !widget.isMultiScan)
          Container(
            decoration: ShapeDecoration(
              shape: widget.scannerOverlay ??
                  ScannerOverlayBorder(
                    cutOutSize: cropSize,
                    horizontalOffset: widget.horizontalCropOffset,
                    verticalOffset: widget.verticalCropOffset,
                    borderColor: Theme.of(context).primaryColor,
                    overlayColor: Colors.black45,
                    borderRadius: 4,
                    borderLength: 20,
                    borderWidth: 8,
                  ),
            ),
          ),
        if (widget.allowPinchZoom)
          GestureDetector(
            onScaleStart: (ScaleStartDetails details) {
              _zoom = _scaleFactor;
            },
            onScaleUpdate: (ScaleUpdateDetails details) {
              if (!_isCameraOn) {
                return;
              }
              _scaleFactor =
                  (_zoom * details.scale).clamp(_minZoomLevel, _maxZoomLevel);
              controller?.setZoomLevel(_scaleFactor);
            },
          ),
        SafeArea(
          child: Align(
            alignment: widget.actionButtonsAlignment,
            child: Padding(
              padding: widget.actionButtonsPadding,
              child: ClipRRect(
                borderRadius: widget.actionButtonsBackgroundBorderRadius ??
                    BorderRadius.circular(10.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius:
                          widget.actionButtonsBackgroundBorderRadius ??
                              BorderRadius.circular(10.0),
                      child: ColoredBox(
                        color: widget.actionButtonsBackgroundColor,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (widget.showFlashlight && _isFlashAvailable)
                              IconButton(
                                onPressed: _onFlashButtonTapped,
                                color: Colors.white,
                                icon: _flashIcon(controller?.value.flashMode ??
                                    FlashMode.off),
                              ),
                            if (widget.showGallery)
                              IconButton(
                                onPressed: _onGalleryButtonTapped,
                                color: Colors.white,
                                icon: widget.galleryIcon,
                              ),
                            if (widget.showToggleCamera)
                              IconButton(
                                onPressed: _onCameraButtonTapped,
                                color: Colors.white,
                                icon: widget.toggleCameraIcon,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (widget.onActionSecondButton != null &&
                        widget.actionSecondButtonIcon != null) ...<Widget>[
                      Container(
                        margin: EdgeInsets.only(
                            bottom: (widget.onMultiScanModeChanged != null &&
                                    widget.multiScanModeAlignment ==
                                        Alignment.bottomRight)
                                ? 55.0
                                : 0),
                        child: IconButton.filled(
                          padding: widget.actionButtonsPadding,
                          onPressed: widget.onActionSecondButton,
                          icon: widget.actionSecondButtonIcon!,
                          style: IconButton.styleFrom(
                            backgroundColor:
                                widget.actionSecondButtonIconBackgroundColor ??
                                    widget.actionButtonsBackgroundColor,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  widget.actionButtonsBackgroundBorderRadius ??
                                      BorderRadius.zero,
                            ),
                          ),
                        ),
                      )
                    ]
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.onMultiScanModeChanged != null)
          SafeArea(
            child: ScanModeDropdown(
              isMultiScan: _isMultiScan,
              alignment: widget.multiScanModeAlignment,
              padding: widget.multiScanModePadding,
              onChanged: (bool value) {
                if (mounted) {
                  setState(() {
                    _isMultiScan = value;
                  });
                }
                widget.onMultiScanModeChanged?.call(value);
              },
            ),
          ),
      ],
    );
  }

  void _onFlashButtonTapped() {
    FlashMode mode = controller?.value.flashMode ?? FlashMode.off;
    if (mode == FlashMode.torch) {
      mode = FlashMode.off;
    } else {
      mode = FlashMode.torch;
    }
    controller?.setFlashMode(mode);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onGalleryButtonTapped() async {
    final XFile? file =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file != null) {
      final DecodeParams params = DecodeParams(
        imageFormat: zxing.ImageFormat.rgb,
        format: widget.codeFormat,
        tryHarder: widget.tryHarder,
        tryInverted: widget.tryInverted,
        isMultiScan: widget.isMultiScan,
      );
      if (widget.isMultiScan) {
        final Codes result = await zx.readBarcodesImagePath(file, params);
        if (result.codes.isNotEmpty) {
          results = result;
          widget.onMultiScan?.call(result);
          if (!mounted) {
            return;
          }
          if (mounted) {
            setState(() {});
          }
        } else {
          results = Codes();
          widget.onMultiScanFailure?.call(result);
        }
      } else {
        final Code result = await zx.readBarcodeImagePath(file, params);
        if (result.isValid) {
          widget.onScan?.call(result);
        } else {
          widget.onScanFailure?.call(result);
        }
      }
    }
  }

  void _onCameraButtonTapped() {
    if (cameras.isEmpty || controller == null) {
      return;
    }
    final int cameraIndex = cameras.indexOf(controller!.description);
    final int nextCameraIndex = (cameraIndex + 1) % cameras.length;
    selectedCamera = cameras[nextCameraIndex];
    onNewCameraSelected(selectedCamera);
  }

  Widget _flashIcon(FlashMode mode) {
    switch (mode) {
      case FlashMode.torch:
        return widget.flashOnIcon;
      case FlashMode.off:
        return widget.flashOffIcon;
      case FlashMode.always:
        return widget.flashAlwaysIcon;
      case FlashMode.auto:
        return widget.flashAutoIcon;
    }
  }

  int _imageFormat(ImageFormatGroup group) {
    switch (group) {
      case ImageFormatGroup.unknown:
        return zxing.ImageFormat.none;
      case ImageFormatGroup.bgra8888:
        return zxing.ImageFormat.bgrx;
      case ImageFormatGroup.yuv420:
        return zxing.ImageFormat.lum;
      case ImageFormatGroup.jpeg:
        return zxing.ImageFormat.rgb;
      case ImageFormatGroup.nv21:
        return zxing.ImageFormat.lum;
    }
  }
}
