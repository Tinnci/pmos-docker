import QtQuick
import QtWebSockets

// Entity store + Home Assistant WebSocket client.
// With an empty `url` it runs on built-in demo data so the UI works offline.
Item {
    id: root

    property string url: ""      // e.g. ws://homeassistant.local:8123/api/websocket
    property string token: ""    // long-lived access token
    readonly property bool demo: url === ""
    property string status: demo ? "demo" : "connecting"
    readonly property alias entities: store
    property var areas: ["Living room", "Kitchen", "Bedroom", "Hall"]

    readonly property var wantedDomains: ["light", "switch", "lock", "climate", "sensor", "scene", "cover"]

    ListModel { id: store }

    function indexOf(entityId) {
        for (var i = 0; i < store.count; ++i)
            if (store.get(i).entityId === entityId) return i
        return -1
    }

    function upsert(e) {
        var i = indexOf(e.entityId)
        if (i < 0) store.append(e)
        else store.set(i, e)
    }

    function inArea(area) {
        var out = []
        for (var i = 0; i < store.count; ++i)
            if (store.get(i).area === area) out.push(store.get(i))
        return out
    }

    function firstOf(domain) {
        for (var i = 0; i < store.count; ++i)
            if (store.get(i).domain === domain) return store.get(i)
        return null
    }

    // ---- actions -------------------------------------------------------
    function activate(entityId) {
        var i = indexOf(entityId)
        if (i < 0) return
        var e = store.get(i)
        if (demo) {
            if (e.domain === "scene") return
            var on = e.state === "on" || e.state === "unlocked" || e.state === "heat"
            var next = on ? (e.domain === "lock" ? "locked" : e.domain === "climate" ? "off" : "off")
                          : (e.domain === "lock" ? "unlocked" : e.domain === "climate" ? "heat" : "on")
            store.setProperty(i, "state", next)
            return
        }
        if (e.domain === "lock")
            callService("lock", e.state === "locked" ? "unlock" : "lock", entityId)
        else if (e.domain === "scene")
            callService("scene", "turn_on", entityId)
        else
            callService("homeassistant", "toggle", entityId)
    }

    function adjust(entityId, delta) {
        var i = indexOf(entityId)
        if (i < 0) return
        var e = store.get(i)
        if (demo) { store.setProperty(i, "value", e.value + delta); return }
        if (e.domain === "climate")
            callService("climate", "set_temperature", entityId, { temperature: e.value + delta })
        else if (e.domain === "light")
            callService("light", "turn_on", entityId,
                        { brightness_pct: Math.max(1, Math.min(100, e.value + delta)) })
    }

    // ---- demo data -----------------------------------------------------
    function seedDemo() {
        var d = [
            ["light.living_main", "Ceiling", "light", "Living room", "on", 70, "%"],
            ["light.living_lamp", "Floor lamp", "light", "Living room", "off", 0, "%"],
            ["climate.living", "Thermostat", "climate", "Living room", "heat", 21.5, "°"],
            ["scene.movie", "Movie night", "scene", "Living room", "scening", 0, ""],
            ["light.kitchen", "Kitchen", "light", "Kitchen", "on", 100, "%"],
            ["switch.coffee", "Coffee maker", "switch", "Kitchen", "off", 0, ""],
            ["sensor.kitchen_temp", "Temperature", "sensor", "Kitchen", "22.4", 22.4, "°"],
            ["light.bedroom", "Bedside", "light", "Bedroom", "off", 0, "%"],
            ["cover.bedroom_blind", "Blinds", "cover", "Bedroom", "open", 100, "%"],
            ["lock.front_door", "Front door", "lock", "Hall", "locked", 0, ""],
            ["light.hall", "Hall light", "light", "Hall", "on", 40, "%"],
            ["scene.goodnight", "Good night", "scene", "Hall", "scening", 0, ""]
        ]
        for (var i = 0; i < d.length; ++i)
            upsert({ entityId: d[i][0], name: d[i][1], domain: d[i][2], area: d[i][3],
                     state: d[i][4], value: d[i][5], unit: d[i][6] })
    }

    // ---- Home Assistant protocol --------------------------------------
    property int _nextId: 1
    property int _statesReq: 0
    property int _entityRegReq: 0
    property var _areaOf: ({})

    function send(msg) {
        msg.id = _nextId++
        socket.sendTextMessage(JSON.stringify(msg))
        return msg.id
    }

    function callService(domain, service, entityId, data) {
        send({ type: "call_service", domain: domain, service: service,
               service_data: data || {}, target: { entity_id: entityId } })
    }

    function fromState(s) {
        var id = s.entity_id
        var domain = id.split(".")[0]
        if (wantedDomains.indexOf(domain) < 0) return null
        var a = s.attributes || {}
        var value = 0, unit = ""
        if (domain === "light") { value = a.brightness ? Math.round(a.brightness / 2.55) : 0; unit = "%" }
        else if (domain === "climate") { value = a.temperature || a.current_temperature || 0; unit = "°" }
        else if (domain === "sensor") {
            if (a.device_class !== "temperature" && a.device_class !== "humidity") return null
            value = parseFloat(s.state) || 0; unit = a.unit_of_measurement || ""
        } else if (domain === "cover") { value = a.current_position || 0; unit = "%" }
        return { entityId: id, name: a.friendly_name || id, domain: domain,
                 area: _areaOf[id] || "Other", state: s.state, value: value, unit: unit }
    }

    function handle(m) {
        if (m.type === "auth_required") {
            socket.sendTextMessage(JSON.stringify({ type: "auth", access_token: token }))
        } else if (m.type === "auth_ok") {
            status = "connected"
            _entityRegReq = send({ type: "config/entity_registry/list" })
        } else if (m.type === "auth_invalid") {
            status = "auth failed"
        } else if (m.type === "result" && m.success) {
            if (m.id === _entityRegReq) {
                var map = {}, seen = {}
                for (var i = 0; i < m.result.length; ++i)
                    if (m.result[i].area_id) {
                        var name = m.result[i].area_id.replace(/_/g, " ")
                        name = name.charAt(0).toUpperCase() + name.slice(1)
                        map[m.result[i].entity_id] = name
                        seen[name] = true
                    }
                _areaOf = map
                var list = Object.keys(seen).sort()
                areas = list.length ? list.concat(["Other"]) : ["Other"]
                _statesReq = send({ type: "get_states" })
                send({ type: "subscribe_events", event_type: "state_changed" })
            } else if (m.id === _statesReq) {
                for (var j = 0; j < m.result.length; ++j) {
                    var e = fromState(m.result[j])
                    if (e) upsert(e)
                }
            }
        } else if (m.type === "event" && m.event && m.event.event_type === "state_changed") {
            var ns = m.event.data.new_state
            if (ns) { var ent = fromState(ns); if (ent) upsert(ent) }
        }
    }

    WebSocket {
        id: socket
        url: root.url
        active: !root.demo
        onTextMessageReceived: function (message) { root.handle(JSON.parse(message)) }
        onStatusChanged: {
            if (status === WebSocket.Error) root.status = "error: " + errorString
            else if (status === WebSocket.Closed && !root.demo) root.status = "disconnected"
        }
    }

    // Reconnect when the socket drops.
    Timer {
        interval: 5000; repeat: true
        running: !root.demo && socket.status !== WebSocket.Open && socket.status !== WebSocket.Connecting
        onTriggered: { socket.active = false; socket.active = true }
    }

    Component.onCompleted: if (demo) seedDemo()
}
