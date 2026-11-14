import QtQuick
import Qt.labs.folderlistmodel

Image {
    id: root
    required property url directory
    property double timestamp: Date.now()
    readonly property int index: files.count > 0 ? Math.floor(timestamp / 3600000) % files.count : -1
    function selectImage() {
        source = index >= 0 ? files.get(index, "fileUrl") : "";
    }
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    onIndexChanged: selectImage()
    FolderListModel {
        id: files
        folder: root.directory
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        caseSensitive: false
        showDirs: false
        sortField: FolderListModel.Name
        onCountChanged: root.selectImage()
        onStatusChanged: if (status === FolderListModel.Ready) root.selectImage()
    }
    Timer {
        interval: Math.max(1, 3600000 - root.timestamp % 3600000)
        running: true
        repeat: true
        onTriggered: root.timestamp = Date.now()
    }
}
