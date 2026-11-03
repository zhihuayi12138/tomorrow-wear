import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/common.dart';

/// 连拍：一次拍很多件，拍完一起处理。
///
/// 为什么不复用系统相机：系统相机一次只回来一张，每件都要
/// 「打开相机 → 拍 → 确认 → 返回」，十几件就是十几轮。
/// 连拍把最贵的那个「返回再点添加」省掉了。
///
/// 几个刻意的做法：
/// 1. **拍完不自动关页**。用户不知道自己拍了多少件，让他自己按「完成」。
/// 2. **快门之间不阻塞**。`takePicture` 有几百毫秒延迟，这期间
///    界面要给出反馈（计数器 +1、缩略图滑入），否则用户会连按。
/// 3. **相机不可用时不留死路**。没有权限或没有摄像头，直接给
///    「从相册选」的出口，而不是一个空白页。
class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  CameraController? _controller;
  final List<Uint8List> _shots = [];
  bool _initializing = true;
  String? _error;

  /// 原始异常文本。只在小字里给，方便排查；不摆在主文案里 ——
  /// 用户看到 MissingPluginException 只会更困惑。
  String? _errorDetail;
  bool _takingPicture = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _error = '这台设备没有可用的摄像头';
        });
        return;
      }
      // 默认用后置：拍平铺的衣服不需要自拍视角。
      final back =
          cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      final controller = CameraController(
        back.isNotEmpty ? back.first : cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = e.code == 'CameraAccessDenied'
            ? '没有相机权限。去系统设置里打开，或者从相册选。'
            : '相机打不开。用相册选也可以。';
        _errorDetail = e.description ?? e.code;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = '相机打不开。用相册选也可以。';
        _errorDetail = '$e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15130F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _shots.isEmpty ? '连拍' : '已拍 ${_shots.length} 件',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: _cancel,
        ),
        actions: [
          if (_shots.isNotEmpty)
            TextButton(
              onPressed: _finish,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('完成', style: TextStyle(fontSize: 14)),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    if (_error != null) {
      return _errorView(_error!);
    }

    final controller = _controller!;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: 1 / controller.value.aspectRatio,
                  child: CameraPreview(controller),
                ),
              ),
              // 取景框：一句「放中间」比任何说明文字都直观。
              IgnorePointer(
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.78,
                    heightFactor: 0.62,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 1.2,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Text(
                  '把衣服平铺在纯色桌面上，放进框里',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_shots.isNotEmpty) _strip(),
        _shutterBar(),
      ],
    );
  }

  Widget _strip() {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        itemCount: _shots.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            _shots[i],
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }

  Widget _shutterBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _shots.isEmpty ? '一件一拍，拍完按完成' : '还能接着拍',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
            GestureDetector(
              onTap: _takingPicture ? null : _shoot,
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _takingPicture ? Colors.white38 : Colors.white,
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: const Color(0xFF15130F), width: 2),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: _shots.isEmpty
                    ? const SizedBox(width: 66)
                    : TextButton(
                        onPressed: _finish,
                        style:
                            TextButton.styleFrom(foregroundColor: Colors.white),
                        child: const Text('完成', style: TextStyle(fontSize: 14)),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                size: 34, color: Colors.white38),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            if (_errorDetail != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorDetail!,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white30),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: 200,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(<Uint8List>[]),
                child: const Text('回去用相册选'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shoot() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() => _takingPicture = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _shots.add(bytes));
      // 轻震一下：连拍时眼睛盯着衣服、不在屏幕上，震动比视觉反馈有效。
      unawaited(HapticFeedback.lightImpact());
    } on CameraException catch (e) {
      if (!mounted) return;
      showToast(context, '这张没拍上：${e.description ?? e.code}');
    } on Object catch (e) {
      if (!mounted) return;
      showToast(context, '这张没拍上：$e');
    } finally {
      if (mounted) setState(() => _takingPicture = false);
    }
  }

  void _cancel() => Navigator.of(context).pop(<Uint8List>[]);

  void _finish() => Navigator.of(context).pop(_shots);
}
