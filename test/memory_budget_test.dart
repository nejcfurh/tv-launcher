import 'package:flauncher/memory_budget.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the GPU cache holds six 1080p screens, and never less than the floor', () {
    expect(gpuResourceCacheBytes(const Size(1920, 1080)), 1920 * 1080 * 4 * 6);
    expect(gpuResourceCacheBytes(Size.zero), kGpuResourceCacheMinBytes);
  });

  test('applying the budget caps the image cache and asks the engine for the GPU cache size', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.skia,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.skia, null);
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
    });

    await applyMemoryBudget(const Size(1920, 1080));

    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, kImageCacheMaxBytes);
    expect(calls.single.method, 'Skia.setResourceCacheMaxBytes');
    expect(calls.single.arguments, 1920 * 1080 * 4 * 6);
  });

  test('an engine that rejects the GPU cache setting still gets the image cache cap', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.skia,
      (call) async => throw PlatformException(code: 'unsupported'),
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.skia, null);
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
    });

    await applyMemoryBudget(const Size(1920, 1080));

    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, kImageCacheMaxBytes);
  });
}
