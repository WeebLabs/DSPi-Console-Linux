import QtQuick 2.15

// Rate-limits live device updates during a drag: push(v) fires at once,
// then at most once per `interval` with the latest value. cancel() drops a
// pending value (call it before the release commits the final one).
Timer {
    id: throttle
    interval: 30
    property var pending
    property bool dirty: false
    signal fire(var value)

    function push(v) {
        if (running) { pending = v; dirty = true; return }
        fire(v)
        start()
    }
    function cancel() { stop(); dirty = false }

    onTriggered: if (dirty) { dirty = false; fire(pending); start() }
}
