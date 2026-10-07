import QtQuick

// A value that breathes between 1 and 0.3 while `active`, for "this step is
// in progress" segments. Shared by the create/prune progress displays
// instead of a separate copy of the same animation in each.
QtObject {
  id: root

  property bool active: false
  property real value: 1

  SequentialAnimation on value {
    running: root.active
    loops: Animation.Infinite
    NumberAnimation { to: 0.3; duration: 650; easing.type: Easing.InOutQuad }
    NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutQuad }
  }
}
