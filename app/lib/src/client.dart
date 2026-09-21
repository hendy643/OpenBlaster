// SPDX-License-Identifier: Apache-2.0
import 'models.dart';

/// Everything the window needs from the hardware. [LocalClient] does it in this process; tests and
/// previews use the same class over made-up hardware.
abstract class OpenBlasterClient {
  Future<List<DeviceRef>> devices();

  /// Fires when a card is added or removed.
  Stream<void> get devicesChanged;

  Future<List<Control>> controls(DeviceRef device);

  /// Throws [ControlError] if the control refuses.
  Future<void> set(DeviceRef device, String id, int value);

  Stream<ControlChange> changes(DeviceRef device);

  /// Things worth telling the user, e.g. that the lighting cannot be reached.
  List<String> get notices;

  Future<void> close();
}
