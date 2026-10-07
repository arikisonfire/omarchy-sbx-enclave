import QtQuick

// Seconds since `since` (a Date.now() timestamp), ticking once a second
// while `active`. Shared by every "a job is in progress" display (create,
// prune, stop/remove) instead of a separate copy of the same Timer in each.
// Item, not QtObject, so it can hold a Timer child.
Item {
  id: root

  property bool active: false
  property double since: 0
  readonly property int seconds: _ticks

  property int _ticks: 0

  Timer {
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: root.active
    onTriggered: root._ticks = root.since > 0 ? Math.round((Date.now() - root.since) / 1000) : 0
  }
}
