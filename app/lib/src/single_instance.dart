// SPDX-License-Identifier: Apache-2.0
import 'package:dbus/dbus.dart';

const _name = 'org.openblaster.OpenBlaster';
const _path = '/org/openblaster/OpenBlaster';

/// org.freedesktop.Application: what a desktop calls to start an app that is already running.
class _Application extends DBusObject {
  _Application(this.onActivate) : super(DBusObjectPath(_path));
  final void Function() onActivate;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == 'org.freedesktop.Application' &&
        call.name == 'Activate') {
      onActivate();
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

/// True if this is the only OpenBlaster; false if another is running, which has been asked to show its
/// window. If there is no session bus we cannot tell, so we carry on.
Future<bool> claimSingleInstance(void Function() onActivate) async {
  try {
    final bus = DBusClient.session();
    final reply = await bus.requestName(
      _name,
      flags: {DBusRequestNameFlag.doNotQueue},
    );
    if (reply == DBusRequestNameReply.primaryOwner) {
      await bus.registerObject(_Application(onActivate));
      return true;
    }
    await bus.callMethod(
      destination: _name,
      path: DBusObjectPath(_path),
      interface: 'org.freedesktop.Application',
      name: 'Activate',
      values: [DBusDict.stringVariant({})],
    );
    await bus.close();
    return false;
  } catch (_) {
    return true;
  }
}
