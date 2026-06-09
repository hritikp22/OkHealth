import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  static const String targetDeviceName = "OkHealth";
  static final Guid serviceUuid =
      Guid("12345678-1234-1234-1234-1234567890ab");
  static final Guid characteristicUuid =
      Guid("abcd1234-5678-90ab-cdef-1234567890ab");

  BluetoothDevice? device;
  BluetoothCharacteristic? characteristic;

  final StreamController<String> _dataController =
      StreamController<String>.broadcast();

  Stream<String> get dataStream => _dataController.stream;

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    }
  }

  Future<void> startScanAndConnect() async {
    await _requestPermissions();

    await FlutterBluePlus.stopScan();

    device = null;
    characteristic = null;

    final completer = Completer<void>();
    late final StreamSubscription<List<ScanResult>> scanSub;

    scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (final result in results) {
        final advName = result.device.platformName;
        final fallbackName = result.advertisementData.advName;

        if (advName == targetDeviceName || fallbackName == targetDeviceName) {
          device = result.device;

          await FlutterBluePlus.stopScan();
          await scanSub.cancel();

          if (!completer.isCompleted) {
            completer.complete();
          }
          return;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

    await Future.any([
      completer.future,
      Future.delayed(const Duration(seconds: 9)),
    ]);

    await FlutterBluePlus.stopScan();
    await scanSub.cancel();

    if (device == null) {
      throw Exception("OkHealth device not found");
    }

    await connectToDevice();
  }

  Future<void> connectToDevice() async {
    if (device == null) return;

    try {
      await device!.connect(timeout: const Duration(seconds: 10));
    } catch (_) {
      // Ignore if already connected
    }

    final services = await device!.discoverServices();

    for (final service in services) {
      if (service.uuid != serviceUuid) continue;

      for (final char in service.characteristics) {
        if (char.uuid == characteristicUuid) {
          characteristic = char;

          await characteristic!.setNotifyValue(true);

          characteristic!.onValueReceived.listen((value) {
            final raw = String.fromCharCodes(value).replaceAll('\u0000', '').trim();
            if (raw.isNotEmpty) {
              _dataController.add(raw);
            }
          });

          final current = await characteristic!.read();
          final firstValue =
              String.fromCharCodes(current).replaceAll('\u0000', '').trim();
          if (firstValue.isNotEmpty) {
            _dataController.add(firstValue);
          }

          return;
        }
      }
    }

    throw Exception("Target BLE characteristic not found");
  }
}