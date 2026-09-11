"""A QAbstractListModel exposing the daemon's device roster to QML.

Mirrors the plasmoid's plain `ListModel` (see ../../package/contents/ui/
main.qml's `devicesModel` and its upsertDevice/removeDevice/
updateDeviceField helpers) role-for-role, so the shared views under
qml/views/ (symlinked to ../../package/contents/ui/views/) - specifically
DeviceListView.qml's `model: micdroid.devicesModel` and its delegate's
`model.serial`/`model.name`/etc. bindings - work completely unmodified
against either a QML ListModel or this Python model.

Role names match state_machine.device_to_dbus_dict's keys exactly:
serial, name, transport, address, state, wifiAdb2Capable, forwardingState.
"""

from __future__ import annotations

from typing import Any

from PySide6.QtCore import QAbstractListModel, QByteArray, QModelIndex, Qt

ROLE_NAMES = [
    "serial", "name", "transport", "address", "state", "wifiAdb2Capable", "forwardingState",
]


class DevicesModel(QAbstractListModel):
    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._devices: list[dict[str, Any]] = []
        self._roles = {Qt.UserRole + i: name for i, name in enumerate(ROLE_NAMES)}

    # --- QAbstractListModel overrides -----------------------------------

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:  # noqa: N802
        return 0 if parent.isValid() else len(self._devices)

    def roleNames(self) -> dict[int, QByteArray]:  # noqa: N802
        return {role: QByteArray(name.encode()) for role, name in self._roles.items()}

    def data(self, index: QModelIndex, role: int = Qt.DisplayRole):  # noqa: N802
        if not index.isValid() or not (0 <= index.row() < len(self._devices)):
            return None
        name = self._roles.get(role)
        if name is None:
            return None
        return self._devices[index.row()].get(name)

    # --- mutation helpers, mirroring main.qml's upsertDevice/removeDevice/
    # updateDeviceField so bridge.py's D-Bus signal handlers can be a
    # near-verbatim port of that logic. -----------------------------------

    def reset(self, devices: list[dict[str, Any]]) -> None:
        self.beginResetModel()
        self._devices = list(devices)
        self.endResetModel()

    def upsert(self, device: dict[str, Any]) -> None:
        serial = device.get("serial")
        for i, d in enumerate(self._devices):
            if d.get("serial") == serial:
                self._devices[i] = device
                idx = self.index(i, 0)
                self.dataChanged.emit(idx, idx)
                return
        self.beginInsertRows(QModelIndex(), len(self._devices), len(self._devices))
        self._devices.append(device)
        self.endInsertRows()

    def remove(self, serial: str) -> None:
        for i, d in enumerate(self._devices):
            if d.get("serial") == serial:
                self.beginRemoveRows(QModelIndex(), i, i)
                del self._devices[i]
                self.endRemoveRows()
                return

    def update_field(self, serial: str, field: str, value: Any) -> None:
        for i, d in enumerate(self._devices):
            if d.get("serial") == serial:
                d[field] = value
                idx = self.index(i, 0)
                self.dataChanged.emit(idx, idx, [])
                return

    def find(self, serial: str) -> dict[str, Any] | None:
        for d in self._devices:
            if d.get("serial") == serial:
                return d
        return None

    def active_states(self) -> list[str]:
        return [d["serial"] for d in self._devices
                if d.get("forwardingState") in ("Forwarding", "DegradedProbing", "Reconnecting")]
