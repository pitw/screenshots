import 'dart:io';

import 'base/platform.dart';
import 'config.dart';
import 'globals.dart';
import 'image_processor.dart';
import 'orientation.dart';
import 'screens.dart';
import 'utils.dart' as utils;

/// Check emulators and simulators are installed, devices attached,
/// matching screen is available and tests exist.
Future<bool> validate(
    Config config, Screens screens, List allDevices, List allEmulators) async {
  final configPath = config.configPath;
  final configInfo = config.configInfo;
  // validate params
  final deviceNames = utils.getAllConfiguredDeviceNames(configInfo);
  for (final devName in deviceNames) {
    final deviceInfo = findDeviceInfo(configInfo, devName);
    if (deviceInfo != null) {
      final orientation = deviceInfo['orientation'];
      if (orientation != null && !isValidOrientation(orientation)) {
        stderr.writeln(
            'Invalid value for \'orientation\' for device \'$devName\': $orientation');
        stderr.writeln('Valid values:');
        for (final orientation in Orientation.values) {
          stderr.writeln('  ${utils.getStringFromEnum(orientation)}');
        }
        exit(1);
      }
      final frame = deviceInfo['frame'];
      if (frame != null && !isValidFrame(frame)) {
        stderr.writeln(
            'Invalid value for \'frame\' for device \'$devName\': $frame');
        stderr.writeln('Valid values:');
        stderr.writeln('  true');
        stderr.writeln('  false');
        exit(1);
      }
    }
  }

  final isDeviceAttached = (device) => device != null;

  if (configInfo['devices']['android'] != null) {
    final devices = utils.getAndroidDevices(allDevices);
    for (String deviceName in configInfo['devices']['android'].keys) {
      if (ImageProcessor.isFrameRequired(
          configInfo, DeviceType.android, deviceName)) {
        // check screen available for this device
        _checkScreenAvailable(screens, deviceName, configPath);
      }

      // check emulator installed
      if (!isDeviceAttached(utils.getDevice(devices, deviceName)) &&
          !isEmulatorInstalled(allEmulators, deviceName)) {
        stderr.write('Error: no device attached or emulator installed for '
            'device \'$deviceName\' in $configPath.\n');
        generateConfigGuide(screens, allDevices);
        exit(1);
      }
    }
  }

  if (configInfo['devices']['ios'] != null) {
    final devices = utils.getIosDevices(allDevices);
    final Map simulators = utils.getIosSimulators();
    for (String deviceName in configInfo['devices']['ios'].keys) {
      if (ImageProcessor.isFrameRequired(
          configInfo, DeviceType.ios, deviceName)) {
        // check screen available for this device
        _checkScreenAvailable(screens, deviceName, configPath);
      }

      // check simulator installed
      if (!isDeviceAttached(utils.getDevice(devices, deviceName)) &&
          !_isSimulatorInstalled(simulators, deviceName)) {
        stderr.write('Error: no device attached or simulator installed for '
            'device \'$deviceName\' in $configPath.\n');
        generateConfigGuide(screens, allDevices);
        exit(1);
      }
    }
  }

  for (String test in configInfo['tests']) {
    if (!isValidTestPaths(test)) {
      stderr.writeln('Invalid config: $test in $configPath');
      exit(1);
    }
  }

  return true;
}

/// Checks all paths are valid.
/// Note: does not cover all uses cases.
bool isValidTestPaths(String driverArgs) {
  final driverPathRegExp = RegExp(r'--driver[= ]+([^\s]+)');
  final targetPathRegExp = RegExp(r'--target[= ]+([^\s]+)');
  final regExps = [driverPathRegExp, targetPathRegExp];

  bool pathExists(String path) {
    if (!File(path).existsSync()) {
      stderr
          .write('File \'$path\' for test config \'$driverArgs\' not found.\n');
      return false;
    }
    return true;
  }

  // Remember any failed path during matching (if any matching)
  bool isInvalidPath = false;
  bool matchFound = false;
  for (final regExp in regExps) {
    final match = regExp.firstMatch(driverArgs);
    if (match != null) {
      matchFound = true;
      final path = match.group(1);
      isInvalidPath = isInvalidPath || !pathExists(path);
    }
  }

  // if invalid path found during matching return, otherwise check default path
  return !(isInvalidPath
      ? isInvalidPath
      : matchFound ? isInvalidPath : !pathExists(driverArgs));
}

/// Check if an emulator is installed.
bool isEmulatorInstalled(List emulators, String deviceName) {
  final emulator = utils.findEmulator(emulators, deviceName);
  final isEmulatorInstalled = emulator != null;

  // check for device installed with multiple avd versions
  if (isEmulatorInstalled) {
    final matchingEmulators =
        emulators.where((emulator) => emulator['name'] == deviceName);
    if (matchingEmulators != null && matchingEmulators.length > 1) {
      print('Warning: \'$deviceName\' has multiple avd versions.');
      print(
          '       : Using \'$deviceName\' with avd version ${emulator['id']}.');
    }
  }
  return isEmulatorInstalled;
}

/// Checks if a simulator is installed, matching the device named in config file.
bool _isSimulatorInstalled(Map simulators, String deviceName) {
  // check simulator installed
  bool isSimulatorInstalled = false;
  simulators.forEach((simulatorName, iOSVersions) {
    //          print('device=$device, simulator=$simulator');
    if (simulatorName == deviceName) {
      // check for duplicate installs
      //            print('os=$os');

      final iOSVersionName = utils.getHighestIosVersion(iOSVersions);
      final udid = iOSVersions[iOSVersionName][0]['udid'];
      // check for device present with multiple os's
      // or with duplicate name
      if (iOSVersions.length > 1 || iOSVersions[iOSVersionName].length > 1) {
        print('Warning: \'$deviceName\' has multiple iOS versions.');
        print(
            '       : Using \'$deviceName\' with iOS version $iOSVersionName (ID: $udid).');
      }

      isSimulatorInstalled = true;
    }
  });
  return isSimulatorInstalled;
}

/// Generate a guide for configuring Screenshots in current environment.
void generateConfigGuide(Screens screens, List devices) {
  stdout.write('\nGuide:');
  _reportAttachedDevices(devices);
  _reportInstalledEmulators(utils.getAvdNames());
  if (platform.isMacOS) _reportInstalledSimulators(utils.getIosSimulators());
  _reportSupportedDevices(screens);
  stdout.write(
      '\n  Each device listed in screenshots.yaml with framing required must'
      '\n    1. have a supported screen'
      '\n    2. have an attached device or an installed emulator/simulator.'
      '\n  To bypass requirement #1 add \'frame: false\' after device in screenshots.yaml\n\n');
}

// check screen is available for device
void _checkScreenAvailable(
    Screens screens, String deviceName, String configPath) {
  final screenProps = screens.screenProps(deviceName);
  if (screenProps == null || _isAndroidModelTypeScreen(screenProps)) {
    stderr.write(
        'Error: screen not available for device \'$deviceName\' in $configPath.\n');
    stderr.flush();
    stdout.write(
        '\n  Use a supported device or set \'frame: false\' for device in $configPath.\n\n'
        '  If framing for device is required, request screen support by\n'
        '  creating an issue in:\n'
        '  https://github.com/mmcc007/screenshots/issues.\n\n');
    _reportSupportedDevices(screens);
    exit(1);
  }
}

void _reportSupportedDevices(Screens screens) {
  stdout.write('\n  Devices with supported screens:\n');
  screens.screens.forEach((os, v) {
    // omit ios devices if not on mac
    if (!(!platform.isMacOS && os == 'ios')) {
      stdout.write('    $os:\n');
      v.forEach((screenId, screenProps) {
        // omit devices that have screens that are
        // only used to identify android model type
        if (!_isAndroidModelTypeScreen(screenProps)) {
          for (String device in screenProps['devices']) {
            stdout.write('      $device\n');
          }
        }
      });
    }
  });
}

/// Test for screen used for identifying android model type
bool _isAndroidModelTypeScreen(screenProps) => screenProps['size'] == null;

void _reportAttachedDevices(List devices) {
  stdout.write('\n  Attached devices:\n');
  for (final device in devices) {
    if (device['emulator'] == false) {
      device['platform'] == 'ios'
          ? stdout.write('    ${device['model']}\n')
          : stdout.write('    ${device['name']}\n');
    }
  }
}

void _reportInstalledEmulators(List emulators) {
  stdout.write('\n  Installed emulators:\n');
  for (final emulator in emulators) {
    stdout.write('    $emulator\n');
  }
}

void _reportInstalledSimulators(Map simulators) {
  stdout.write('  Installed simulators:\n');
  simulators.forEach((simulator, _) => stdout.write('    $simulator\n'));
}

bool isValidOrientation(String orientation) {
  return Orientation.values.firstWhere(
          (o) => utils.getStringFromEnum(o) == orientation,
          orElse: () => null) !=
      null;
}

bool isValidFrame(dynamic frame) {
  return frame != null && (frame == true || frame == false);
}

/// Find device info in config for device name.
Map findDeviceInfo(Map configInfo, String deviceName) {
  Map deviceInfo;
  configInfo['devices'].forEach((deviceType, devices) {
    if (devices != null) {
      devices.forEach((_deviceName, _deviceInfo) {
        if (_deviceName == deviceName) deviceInfo = _deviceInfo;
      });
    }
  });
  return deviceInfo;
}
