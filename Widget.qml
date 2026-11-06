import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// NeuralDeep balance on the bar; wallet, usage meters, and model pricing in
// a popup. Data comes from bin/neuraldeep, which talks to /v1/limits and
// /v1/models and always prints normalized JSON.
Panel {
  id: root

  moduleName: "miron.neuraldeep"
  ipcTarget: "miron.neuraldeep"

  readonly property string script:
    Qt.resolvedUrl("bin/neuraldeep").toString().replace(/^file:\/\//, "")

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property int refreshSec: Math.max(30, Number(setting("refreshSec", 300)) || 300)

  property var snapshot: null
  property bool loading: false
  property string error: ""

  readonly property var wallet: snapshot && snapshot.wallet ? snapshot.wallet : null
  readonly property var daily: snapshot && snapshot.daily ? snapshot.daily : null
  readonly property var session: snapshot && snapshot.chat && snapshot.chat.session ? snapshot.chat.session : null
  readonly property var week: snapshot && snapshot.chat && snapshot.chat.week ? snapshot.chat.week : null
  readonly property var models: snapshot && Array.isArray(snapshot.models) ? snapshot.models : []
  readonly property real balance: wallet && wallet.balance !== null ? wallet.balance : NaN

  // ---------------------------------------------------------------- fetching

  function refresh() {
    if (fetch.running) return
    loading = true
    fetch.running = true
  }

  function apply(raw) {
    loading = false
    var parsed = null
    try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
    if (!parsed || parsed.ok !== true) {
      error = parsed && parsed.error ? String(parsed.error) : "parse"
      snapshot = null
      return
    }
    error = ""
    snapshot = parsed
  }

  Process {
    id: fetch
    command: [root.script]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
    onExited: function(code) {
      root.loading = false
      if (root.snapshot === null && root.error === "")
        root.error = code === 0 ? "parse" : "unreachable"
    }
  }

  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  onOpenedChanged: if (opened) refresh()

  // ---------------------------------------------------------------- formatting

  function money(value, decimals) {
    if (value === null || value === undefined || isNaN(value)) return "—"
    return Commons.I18n.formatNumber(value, decimals === undefined ? 2 : decimals)
  }

  function contextLabel(value) {
    if (!value) return "—"
    if (value >= 1000000) return Commons.I18n.formatNumber(value / 1000000, 1) + "M"
    return Commons.I18n.formatNumber(value / 1000, 0) + "K"
  }

  function shortText(value) {
    return value === null || value === undefined ? "" : String(value).slice(0, 24)
  }

  function statusText() {
    var parts = []
    if (snapshot && snapshot.tier) parts.push(shortText(snapshot.tier))
    if (snapshot && snapshot.key && snapshot.key.status) parts.push(shortText(snapshot.key.status))
    return parts.join(" · ")
  }

  function errorText() {
    if (error === "no-key") return strings.t("error.noKey")
    return strings.t("error.fetch")
  }

  function tooltipText() {
    if (!isNaN(balance)) return strings.t("tooltip").arg(money(balance, 0))
    return strings.t("title")
  }

  // --------------------------------------------------------------------- bar

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "₽ " + root.money(root.balance, 0)
    fontSize: Style.font.bodySmall
    horizontalMargin: 6
    tooltipText: root.tooltipText()
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  // ------------------------------------------------------------------- popup

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(body.implicitHeight)

    Column {
      id: body
      width: parent.width
      spacing: Style.space(8)

      Item {
        width: parent.width
        height: Math.max(title.implicitHeight, status.implicitHeight)

        Label {
          id: title
          text: strings.t("title")
          font.pixelSize: Style.font.heading
          font.bold: true
          color: Color.accent
        }
        Label {
          id: status
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.statusText()
          color: Color.muted
        }
      }

      Label {
        visible: root.error !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        color: Color.urgent
        text: root.error !== "" ? root.errorText() : ""
      }

      Label {
        visible: root.snapshot === null && root.error === "" && root.loading
        text: strings.t("loading")
        color: Color.muted
      }

      Column {
        visible: root.snapshot !== null
        width: parent.width
        spacing: Style.space(8)

        Label {
          text: root.money(root.balance, 2) + " ₽"
          font.pixelSize: Style.font.display
          font.bold: true
          color: Color.accent
        }

        Label {
          width: parent.width
          wrapMode: Text.WordWrap
          color: Color.muted
          text: root.wallet != null && root.wallet.spent30d != null
            ? strings.t("spent30d").arg(root.money(root.wallet.spent30d, 2))
            : ""
        }

        Meter {
          visible: root.daily != null && root.daily.pct != null
          label: strings.t("daily")
          value: root.daily ? root.money(root.daily.pct, 0) + "%" : ""
          fraction: root.daily != null && root.daily.pct != null ? root.daily.pct / 100 : 0
        }

        Meter {
          visible: root.session != null && root.session.limit != null
          label: strings.t("session")
          value: root.session ? root.money(root.session.used, 0) + " / " + root.money(root.session.limit, 0) : ""
          fraction: root.session != null && root.session.limit != null ? root.session.used / root.session.limit : 0
        }

        Meter {
          visible: root.week != null && root.week.limit != null
          label: strings.t("week")
          value: root.week ? root.money(root.week.used, 0) + " / " + root.money(root.week.limit, 0) : ""
          fraction: root.week != null && root.week.limit != null ? root.week.used / root.week.limit : 0
        }

        Label {
          visible: root.snapshot != null && root.snapshot.parallelLimit != null
          color: Color.muted
          text: root.snapshot != null && root.snapshot.parallelLimit != null
            ? strings.t("parallel").arg(root.money(root.snapshot.parallelLimit, 0))
            : ""
        }

        Label {
          visible: root.snapshot != null && root.snapshot.night != null && root.snapshot.night.active === true
          color: Color.muted
          text: strings.t("nightActive")
        }

        PanelSeparator { visible: root.models.length > 0 }

        Item {
          visible: root.models.length > 0
          width: parent.width
          height: section.implicitHeight

          PanelSectionHeader {
            id: section
            text: strings.t("models")
          }
          Label {
            anchors.right: parent.right
            anchors.verticalCenter: section.verticalCenter
            text: Commons.I18n.formatNumber(root.models.length, 0)
            color: Color.muted
          }
        }

        Item {
          visible: root.models.length > 0
          width: parent.width
          height: Math.max(colModel.implicitHeight, colContext.implicitHeight, colPrice.implicitHeight)

          Label {
            id: colModel
            text: strings.t("col.model")
            color: Color.muted
            font.pixelSize: Style.font.caption
          }
          Label {
            id: colContext
            x: parent.width * 0.44
            text: strings.t("col.context")
            color: Color.muted
            font.pixelSize: Style.font.caption
          }
          Label {
            id: colPrice
            anchors.right: parent.right
            text: strings.t("col.price")
            color: Color.muted
            font.pixelSize: Style.font.caption
          }
        }

        ListView {
          id: modelList
          visible: root.models.length > 0
          width: parent.width
          height: Math.min(count, 8) * Style.spacing.popupRowHeight
          clip: true
          model: root.models

          delegate: Item {
            width: modelList.width
            height: Style.spacing.popupRowHeight

            Label {
              width: parent.width * 0.42
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: root.shortText(modelData.id)
            }
            Label {
              x: parent.width * 0.44
              width: parent.width * 0.20
              anchors.verticalCenter: parent.verticalCenter
              color: Color.muted
              text: root.contextLabel(modelData.context)
            }
            Label {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              text: root.money(modelData.input, 2) + " / " + root.money(modelData.output, 2)
            }
          }
        }
      }
    }
  }

  // Small plain-text label; every value from the API renders through it.
  component Label: Text {
    textFormat: Text.PlainText
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  component Meter: Column {
    id: meter
    property string label: ""
    property string value: ""
    property real fraction: 0

    width: parent ? parent.width : 0
    spacing: Style.space(3)

    Item {
      width: parent.width
      height: Math.max(labelText.implicitHeight, valueText.implicitHeight)

      Label {
        id: labelText
        text: meter.label
      }
      Label {
        id: valueText
        anchors.right: parent.right
        text: meter.value
        color: Color.muted
      }
    }

    Rectangle {
      width: parent.width
      height: Style.space(4)
      radius: height / 2
      color: Util.alpha(Color.foreground, 0.15)

      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, meter.fraction))
        height: parent.height
        radius: parent.radius
        color: Color.accent
      }
    }
  }
}