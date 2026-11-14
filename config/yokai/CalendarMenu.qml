import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

AttachedPopup {
    id: root
    property date today: new Date()
    property date shownMonth: new Date(today.getFullYear(), today.getMonth(), 1)
    property date selectedDate: today
    heading: "Calendar"
    implicitWidth: 346
    implicitHeight: 348
    function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate(); }
    function shiftMonth(direction) { shownMonth = new Date(shownMonth.getFullYear(), shownMonth.getMonth() + direction, 1); }
    function goToday() { shownMonth = new Date(today.getFullYear(), today.getMonth(), 1); selectedDate = today; }
    onVisibleChanged: if (visible) goToday()
    ColumnLayout {
        anchors.fill: parent
        anchors { leftMargin: 34; rightMargin: 20; topMargin: 20; bottomMargin: 18 }
        spacing: 12
        RowLayout {
            TextLabel { Layout.fillWidth: true; text: grid.title; font.pixelSize: 16; font.weight: Font.Medium }
            YokaiButton { text: "‹"; implicitWidth: 28; onClicked: root.shiftMonth(-1) }
            YokaiButton { text: "›"; implicitWidth: 28; onClicked: root.shiftMonth(1) }
        }
        DayOfWeekRow {
            Layout.fillWidth: true; Layout.preferredHeight: 20
            locale: grid.locale
            delegate: TextLabel {
                required property string shortName
                text: shortName; font.pixelSize: 10; color: Theme.muted
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
        }
        MonthGrid {
            id: grid
            Layout.fillWidth: true; Layout.fillHeight: true
            month: root.shownMonth.getMonth()
            year: root.shownMonth.getFullYear()
            locale: Qt.locale("en_GB")
            spacing: 3
            delegate: Rectangle {
                id: day
                required property var model
                readonly property bool selected: root.sameDay(model.date, root.selectedDate)
                readonly property bool current: root.sameDay(model.date, root.today)
                radius: 4
                color: selected ? Theme.selection : mouse.containsMouse ? Theme.elevated : "transparent"
                border.width: 1; border.color: current ? Theme.vermilion : "transparent"
                opacity: model.month === grid.month ? 1 : .35
                TextLabel { anchors.centerIn: parent; text: day.model.day; font.pixelSize: 12; font.family: "JetBrains Mono" }
                MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.selectedDate = day.model.date }
            }
        }
        RowLayout {
            TextLabel { Layout.fillWidth: true; text: root.selectedDate.toLocaleDateString(Qt.locale("en_GB"), "ddd, d MMM yyyy"); color: Theme.muted; font.pixelSize: 11 }
            YokaiButton { text: "Today"; implicitHeight: 28; onClicked: root.goToday() }
        }
    }
}
