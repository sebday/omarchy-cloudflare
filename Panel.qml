import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Api.js" as Api
import "Model.js" as Model
import "components"

Panel {
  id: root
  moduleName: "evo.cloudflare"
  ipcTarget: "evo.cloudflare"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color surface: Color.popups.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var cf: hostWidget && hostWidget.cf ? hostWidget.cf : null

  readonly property string accountLegendLabel: {
    if (!cf)
      return ""
    void cf.accountName
    void cf.accountId
    if (cf.accountName !== "")
      return cf.accountName
    return ""
  }

  property double nowMs: Date.now()

  readonly property var rows: {
    if (!cf)
      return []
    void cf.lastRefreshMs
    void cf.loggedIn
    void cf.accountId
    void cf.refreshing
    void cf.analyticsRefreshing
    void cf.workers.length
    void cf.pages.length
    void cf.buckets.length
    void cf.databases.length
    void cf.namespaces.length
    void cf.queues.length
    void cf.zones.length
    void cf.analytics.loaded
    void cf.analytics.workerRequests
    void cf.analytics.workerErrors
    void cf.analytics.r2Bytes
    void cf.analytics.d1RowsRead
    return buildRows()
  }

  readonly property var groupedSections: {
    var sourceRows = root.rows
    void sourceRows.length
    return groupedSectionsFromRows(sourceRows)
  }

  readonly property var usageSection: sectionByTitle("USAGE")
  readonly property var resourcesSection: sectionByTitle("RESOURCES")
  readonly property var attentionSection: sectionByTitle("NEEDS ATTENTION")
  readonly property var recentGroupedSection: sectionByTitle("RECENT ACTIVITY")

  readonly property bool hasDisplaySections:
    root.usageSection.rows.length > 0
    || root.resourcesSection.rows.length > 0
    || root.attentionSection.rows.length > 0
    || root.recentGroupedSection.rows.length > 0

  readonly property bool iconActive: cf && cf.loggedIn && !cf.warning
  readonly property string barTooltip: {
    if (!cf) return "Cloudflare"
    if (cf.accountName !== "") return Model.plain(cf.accountName)
    if (cf.lastError !== "") return Model.plain(cf.lastError)
    return cf.loggedIn ? "Cloudflare" : "Cloudflare — not logged in"
  }

  function sectionByTitle(title) {
    var sections = root.groupedSections
    void sections.length
    for (var i = 0; i < sections.length; i++) {
      if (String(sections[i].title || "").toUpperCase() === title)
        return sections[i]
    }
    return { title: title, rows: [] }
  }

  function buildRows() {
    if (!cf)
      return []
    return Model.buildRows(cf.resourceState(), cf.analytics, {
      deployRows: cf.deployRows,
      overviewDeployRows: cf.overviewDeployRows,
      limits: cf.limits,
      filter: "",
      route: "",
      tokenRows: Api.tokenShortcuts(cf.accountId)
    })
  }

  function groupedSectionsFromRows(sourceRows) {
    var rows = sourceRows || []
    var out = []
    var currentKey = null
    var current = null
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var key = String(row.section !== undefined ? row.section : "")
      if (key !== currentKey) {
        currentKey = key
        var sectionTitle = String(row.sectionTitle || row.section || "")
        if (!sectionTitle && row.kind === "group" && row.target === "token")
          sectionTitle = "CREATE A TOKEN"
        current = { title: sectionTitle, key: key, rows: [] }
        out.push(current)
      }
      if (current)
        current.rows.push(row)
    }
    return out.filter(function(section) {
      return String(section.title || "") !== "CREATE A TOKEN"
    })
  }

  function openRow(row) {
    if (!row || !cf)
      return
    if (row.kind === "usage")
      cf.refreshAnalytics()
    else if (row.kind === "empty" || row.kind === "note")
      return
    else if (row.kind === "group") {
      if (row.target === "token")
        cf.openUrl(Api.dashAccount("/api-tokens", cf.accountId))
      else if (row.target === "worker")
        cf.openUrl(Api.dashAccount("/workers", cf.accountId))
      else if (row.target === "pages")
        cf.openUrl(Api.dashAccount("/pages", cf.accountId))
      else if (row.target === "r2")
        cf.openUrl(Api.dashAccount("/r2", cf.accountId))
      else if (row.target === "d1")
        cf.openUrl(Api.dashAccount("/workers/d1", cf.accountId))
      else if (row.target === "kv")
        cf.openUrl(Api.dashAccount("/workers/kv", cf.accountId))
      else if (row.target === "queue")
        cf.openUrl(Api.dashAccount("/workers/queues", cf.accountId))
      else if (row.target === "zone")
        cf.openUrl(Api.dashAccount("/zones", cf.accountId))
    } else if (row.kind === "deploy")
      cf.openUrl(Api.dashUrlFor(row, cf.accountId))
    else if (row.liveUrl)
      cf.openUrl(row.liveUrl)
    else
      cf.openUrl(Api.dashUrlFor(row, cf.accountId))
  }

  function rowGlyph(row) {
    if (!row)
      return ""
    if (row.kind === "deploy")
      return Model.glyphFor(row.target === "pages" ? "pages" : "worker")
    if (row.kind === "group")
      return Model.glyphFor(row.target === "token" ? "token" : row.target)
    return Model.glyphFor(row.kind)
  }

  function rowTitle(row) {
    if (!row)
      return ""
    if (row.kind === "usage")
      return String(row.title || "")
    if (row.kind === "group" && row.target === "token")
      return String(row.name || "Create a token")
    if (row.kind === "group")
      return String(row.name || "")
    return String(row.name || row.title || "")
  }

  function statValue(row) {
    if (!row)
      return "—"
    if (row.kind === "usage")
      return usageStatValue(row)
    if (row.kind === "group")
      return String(row.count !== undefined ? row.count : "—")
    return "—"
  }

  function usageStatValue(row) {
    if (!cf || !cf.analytics || !cf.analytics.loaded)
      return "—"
    if (row.metered && row.percent >= 0)
      return Math.round(row.percent * 100) + "%"
    var a = cf.analytics
    switch (String(row.id || "")) {
    case "worker-requests":
      return Model.formatCount(a.workerRequests)
    case "worker-errors":
      return Model.formatCount(a.workerErrors)
    case "r2-storage":
      return Model.formatBytes(a.r2Bytes)
    case "d1-reads":
      return Model.formatCount(a.d1RowsRead)
    default:
      return "—"
    }
  }

  function usageStatLabel(row) {
    if (!row)
      return ""
    switch (String(row.id || "")) {
    case "worker-requests":
      return "24h requests"
    case "worker-errors":
      return "24h errors"
    case "r2-storage":
      if (!cf || !cf.analytics || !cf.analytics.loaded)
        return "R2 objects"
      return Model.formatCount(cf.analytics.r2Objects) + " R2 objects"
    case "d1-reads":
      return "24h D1 reads"
    default:
      return ""
    }
  }

  function statLabel(row) {
    if (!row)
      return ""
    if (row.kind === "usage")
      return usageStatLabel(row)
    if (row.kind === "group")
      return String(row.name || "")
    return ""
  }

  function statValueColor(row) {
    if (!row)
      return accent
    if (row.alarming || (row.kind === "usage" && row.metered && row.percent >= 0.9))
      return urgent
    return accent
  }

  function rowClickable(row) {
    return row && row.selectable !== false
      && row.kind !== "empty"
      && row.kind !== "note"
  }

  function deployStatusLabel(row) {
    if (!row || row.kind !== "deploy")
      return ""
    if (row.failed)
      return "Failed"
    if (row.building)
      return "Building"
    var status = String(row.status || "deployed").toLowerCase()
    if (status === "deployed" || status === "success")
      return "Deployed"
    return status.charAt(0).toUpperCase() + status.slice(1)
  }

  function deployStatusColor(row) {
    if (!row)
      return foreground
    if (row.failed || row.alarming)
      return urgent
    if (row.building)
      return accent
    return accent
  }

  function deployMetaLine(row) {
    if (!row || row.kind !== "deploy")
      return ""
    var parts = []
    parts.push(row.target === "pages" ? "Pages" : "Worker")
    if (row.via)
      parts.push(String(row.via))
    var time = deployTimeLabel(row)
    if (time)
      parts.push(time)
    return parts.join(" · ")
  }

  function deployTimeLabel(row) {
    if (!row || row.kind !== "deploy" || !row.whenMs)
      return ""
    return Model.relativeTime(row.whenMs, root.nowMs)
  }

  function activityStatusLabel(row) {
    if (!row)
      return ""
    if (row.kind === "deploy")
      return deployStatusLabel(row)
    if (row.alarming)
      return "Alert"
    return ""
  }

  function activityTimeLabel(row) {
    if (!row)
      return ""
    if (row.kind === "deploy")
      return deployTimeLabel(row)
    return ""
  }

  function activityStatusColor(row) {
    if (!row)
      return foreground
    if (row.kind === "deploy")
      return deployStatusColor(row)
    if (row.alarming)
      return urgent
    return accent
  }

  function refresh() {
    if (!cf) return
    cf.refresh()
    if (!cf.analytics.loaded)
      cf.refreshAnalytics()
  }

  function openDashboard() {
    if (cf && typeof cf.openUrl === "function")
      cf.openUrl("https://dash.cloudflare.com")
    root.close()
  }

  function openFromHotkey() {
    root.controller.show()
    refresh()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      nowMs = Date.now()
      refresh()
      tickTimer.start()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      tickTimer.stop()
    }
  }

  Timer {
    id: tickTimer
    interval: 30000
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }



  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
          root.bar.switchPanelFrom(root.barIdentity, direction)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.accountLegendLabel || "Cloudflare"
            meta: cf && cf.actionStatus !== "" ? cf.actionStatus : (cf && cf.busy ? "Refreshing…" : "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.iconActive ? 1 : 0.7

            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰊠"
                color: cf && cf.warning ? root.urgent : root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                opacity: 0.92
              }
            }
          }

          PanelSectionHeader {
            visible: root.usageSection.rows.length > 0
            width: parent.width
            text: "USAGE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(8)
            visible: root.usageSection.rows.length > 0

            Repeater {
              model: root.usageSection.rows

              StatTile {
                required property var modelData
                Layout.fillWidth: true
                value: root.statValue(modelData)
                label: root.statLabel(modelData)
                valueColor: root.statValueColor(modelData)
                clickable: root.rowClickable(modelData)
                onClicked: root.openRow(modelData)
              }
            }
          }

          PanelSectionHeader {
            visible: root.resourcesSection.rows.length > 0
            width: parent.width
            text: "RESOURCES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          GridLayout {
            width: parent.width
            columns: 3
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(8)
            visible: root.resourcesSection.rows.length > 0

            Repeater {
              model: root.resourcesSection.rows

              StatTile {
                required property var modelData
                Layout.fillWidth: true
                value: root.statValue(modelData)
                label: root.statLabel(modelData)
                valueColor: root.statValueColor(modelData)
                clickable: root.rowClickable(modelData)
                onClicked: root.openRow(modelData)
              }
            }
          }

          PanelSectionHeader {
            visible: root.attentionSection.rows.length > 0
            width: parent.width
            text: "NEEDS ATTENTION"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: 0
            visible: root.attentionSection.rows.length > 0

            Repeater {
              model: root.attentionSection.rows

              ActivityEntry {
                required property var modelData
                required property int index
                width: column.width
                row: modelData
                host: root
                showDivider: index < root.attentionSection.rows.length - 1
              }
            }
          }

          PanelSectionHeader {
            visible: root.recentGroupedSection.rows.length > 0
            width: parent.width
            text: "RECENT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: 0
            visible: root.recentGroupedSection.rows.length > 0

            Repeater {
              model: root.recentGroupedSection.rows

              ActivityEntry {
                required property var modelData
                required property int index
                width: column.width
                row: modelData
                host: root
                showDivider: index < root.recentGroupedSection.rows.length - 1
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: !!(cf && cf.lastError)
            text: (cf && cf.lastError) ? cf.lastError : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: !root.hasDisplaySections && (!cf || cf.lastError === "")
            text: !cf ? "Loading…" : (cf.busy ? "Loading…" : (cf.loggedIn ? "No data" : "Not logged in"))
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component StatTile: BorderSurface {
    id: tile
    property string value: ""
    property string label: ""
    property color valueColor: root.accent
    property bool clickable: false

    signal clicked()

    implicitHeight: tileColumn.implicitHeight + Style.spacing.lg * 2
    color: Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
    radius: Style.cornerRadius

    Column {
      id: tileColumn
      anchors.centerIn: parent
      width: parent.width - Style.spacing.lg * 2
      spacing: Style.spacing.labelGap

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: tile.value
        color: tile.valueColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: tile.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: tile.clickable
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: tile.clicked()
    }
  }
}
