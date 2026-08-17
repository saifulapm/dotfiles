import QtQuick
import "../components"
import "../../../components"

// Weather — port of omarchy's weather plugin bar button (CREDITS.md). The
// bar slot carries the condition glyph and the temperature; the panel is the
// detail view; everything they read lives in WeatherService, ONE instance at
// the bar root shared by every screen's copy of this widget (S2).
BarButton {
    id: rootItem

    // The shared fetch stack, injected by the bar's registry.
    required property WeatherService weather

    visible: weather.label !== ""
    tooltipText: weather.current ? (weather.reportDescription + " · feels like " + weather.reportFeels) : ""

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("WeatherPanel.qml", {
                theme: rootItem.theme,
                weather: rootItem.weather
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
        if (panelLoader.item.opened)
            weather.refresh();
    }

    onTapped: button => {
        if (button === Qt.MiddleButton)
            weather.refresh();
        else
            openPanel();
    }

    OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        text: rootItem.weather.label
        color: rootItem.contentColor
        pixelSize: 13
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    StyledText {
        theme: rootItem.theme
        mono: true

        anchors.verticalCenter: parent.verticalCenter
        // Their weather bar widget is glyph-only; ours adds the temperature,
        // which is the part that has no room on a vertical bar.
        visible: !rootItem.vertical && rootItem.weather.reportTempNum !== ""
        text: rootItem.weather.reportTempNum + "°"
        color: rootItem.contentColor
        renderType: Text.NativeRendering
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}
