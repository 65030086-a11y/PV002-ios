# PowerView Manager — App Architecture Document

> Flutter app สำหรับเชื่อมต่อและจัดการ **PowerView Device** (Raspberry Pi)
> ผ่าน TCP/IP (LAN) หรือ USB Serial

---

## 1. Overview

```
┌──────────────────────────────────────────────────────────┐
│                    PowerView Manager                      │
│                                                           │
│  ┌──────────┐    TCP/UDP     ┌──────────────────────┐    │
│  │  Flutter │◄──────────────►│  PowerView Device    │    │
│  │   App    │    USB Serial  │  (Raspberry Pi)      │    │
│  └──────────┘                │  · PyQt5 Dashboard   │    │
│                              │  · Modbus RTU Reader │    │
│                              │  · MQTT Publisher    │    │
│                              └──────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

**สิ่งที่ app ทำได้:**
- ค้นหาอุปกรณ์บน LAN ผ่าน UDP broadcast (discovery)
- ดู dashboard เดียวกับที่ Pi แสดงอยู่ (mirror)
- อ่านข้อมูลมิเตอร์แบบ real-time (V, I, kW, kVAR, kVA, PF, THD, ฯลฯ)
- ดูประวัติพลังงานย้อนหลัง (playback)
- ตั้งค่าทุกอย่างบน Pi ผ่าน app (WiFi, IP, CT, Source, MQTT, Alarm ฯลฯ)

---

## 2. Navigation Architecture

### 2.1 ภาพรวม Flow

```
App Start
    │
    ▼
┌─────────────────────┐
│   ConnectionPage    │  ← Pre-connection
│  ┌───────┬───────┐  │
│  │  TCP  │  USB  │  │
│  └───────┴───────┘  │
│  (UDP discovery /   │
│   manual IP entry)  │
└────────┬────────────┘
         │ เชื่อมต่อสำเร็จ
         ▼
┌─────────────────────────────────────────────────────┐
│                    MainPage                          │
│                                                     │
│  AppBar: [= Menu]  [Device Name]  [● Connected]    │
│  ─────────────────────────────────────────────────  │
│                                                     │
│  ┌───────────┐ ┌──────────┐ ┌─────────┐ ┌───────┐  │
│  │ Dashboard │ │   Live   │ │ History │ │Setting│  │
│  │    [0]    │ │  Data[1] │ │   [2]   │ │  [3]  │  │
│  └───────────┘ └──────────┘ └─────────┘ └───────┘  │
│  NavigationBar (phone) / NavigationRail (tablet)    │
└─────────────────────────────────────────────────────┘
```

### 2.2 Navigation Tabs (4 หลัก)

| # | Tab | Icon | คำอธิบาย |
|---|-----|------|----------|
| 0 | **Dashboard** | `dashboard_outlined` | mirror Pi display + playlist |
| 1 | **Live Data** | `electric_bolt_outlined` | ข้อมูลมิเตอร์ real-time |
| 2 | **History** | `bar_chart_outlined` | ประวัติพลังงานย้อนหลัง |
| 3 | **Settings** | `tune` | ตั้งค่าทั้งหมด |

> บน **tablet / desktop** ใช้ `NavigationRail` แนวตั้งด้านซ้าย
> บน **phone** ใช้ `NavigationBar` ด้านล่าง

---

## 3. Screen Map (ทุกหน้า)

```
MainPage
├── [0] DashboardTab
│   ├── DashboardView              — แสดง SVG/WebView mirror จาก Pi
│   └── PlaylistManagerSheet       — bottom sheet จัดการ playlist
│       ├── DashboardTile          — แต่ละ dashboard (ลากเรียง / ตั้งเวลา)
│       └── AddDashboardButton
│
├── [1] LiveDataTab
│   └── MeterDataPage              — EXISTING
│       ├── SummaryCard            — Total kW, kVAR, kVA, PF, Hz, Temp
│       ├── PhaseCard              — ตาราง L1/L2/L3
│       └── EnergyCard             — kWh, kVARh, kVAh, ค่าไฟ, carbon
│
├── [2] HistoryTab
│   └── EnergyHistoryPage          — PLANNED
│       ├── DateRangePicker
│       ├── LineChart / BarChart
│       └── ExportButton
│
└── [3] SettingsTab
    └── SettingsMenuPage            — grouped list (เหมือน Android Settings)
        │
        ├── [METER] ────────────────────────────────────────────
        ├── DataSourcePage          — REFACTOR (จาก SourceListView)
        │   ├── CollectorPanel      — CT type, Reset Wh, Modbus Slave mode
        │   └── ExternalMeterPanel  — profile, port, baudrate, slave ID
        │
        ├── MeasurementsPage        — EXISTING (PiPowerViewPage บางส่วน)
        │   ├── ElectricityRate     — บาท/kWh
        │   └── CarbonFactor        — kgCO2/kWh
        │
        ├── [NOTIFICATIONS] ────────────────────────────────────
        ├── AlarmSettingsPage       — PLANNED
        │   ├── VoltageAlarm        — V> / V< threshold per phase
        │   └── CurrentAlarm        — A> / A< threshold per phase
        │
        ├── [CONNECTIVITY] ─────────────────────────────────────
        ├── MqttSettingsPage        — PLANNED
        │   ├── EnableToggle
        │   ├── BrokerHost / Port
        │   ├── TopicPrefix
        │   ├── DataSelector        — checkbox list (V, I, kW, kWh ฯลฯ)
        │   └── PublishInterval     — seconds
        │
        ├── WifiPage                — EXISTING (PiWifiPage)
        │   ├── CurrentSsidBanner
        │   ├── NewSsidField + ScanButton
        │   └── PasswordField
        │
        ├── NetworkPage             — EXISTING (PiNetworkPage)
        │   ├── DhcpToggle
        │   ├── IP / Netmask / Gateway / DNS
        │   └── TcpPort
        │
        ├── [SYSTEM] ───────────────────────────────────────────
        ├── SecurityPage            — PLANNED
        │   ├── EnableToggle
        │   ├── UsernameField
        │   └── PasswordField
        │
        └── AboutPage               — PLANNED
            ├── SoftwareVersion
            ├── FirmwareVersion
            ├── SerialNumber
            └── FirmwareUpdateButton
```

---

## 4. Settings Menu — Visual Layout

Settings หน้าแรกเป็น `ListView` แบ่ง group ตาม Material 3 pattern:

```
┌──────────────────────────────────────┐
│  <- Settings                         │
├──────────────────────────────────────┤
│  METER                               │
│  ┌────────────────────────────────┐  │
│  │  Data Source              >   │  │
│  │  Collector · External Modbus  │  │
│  ├────────────────────────────────┤  │
│  │  Measurements             >   │  │
│  │  Rate: 4.00 บาท/kWh           │  │
│  └────────────────────────────────┘  │
│                                      │
│  NOTIFICATIONS                       │
│  ┌────────────────────────────────┐  │
│  │  Alarms                   >   │  │
│  │  No alarms configured         │  │
│  └────────────────────────────────┘  │
│                                      │
│  CONNECTIVITY                        │
│  ┌────────────────────────────────┐  │
│  │  MQTT                     >   │  │
│  │  Disabled                     │  │
│  ├────────────────────────────────┤  │
│  │  WiFi                     >   │  │
│  │  Connected: MyNetwork         │  │
│  ├────────────────────────────────┤  │
│  │  Network                  >   │  │
│  │  DHCP · 192.168.1.42          │  │
│  └────────────────────────────────┘  │
│                                      │
│  SYSTEM                              │
│  ┌────────────────────────────────┐  │
│  │  Security                 >   │  │
│  │  Disabled                     │  │
│  ├────────────────────────────────┤  │
│  │  About & Info             >   │  │
│  │  v0.1.0 · SN: PV-000001       │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

---

## 5. Connection Page

```
┌──────────────────────────────────────┐
│         PowerView Manager            │
│           [App Logo]                 │
├──────────────────────────────────────┤
│  ┌─────────────┬──────────────┐      │
│  │  TCP / LAN  │     USB      │      │
│  └─────────────┴──────────────┘      │
│                                      │
│  --- Scan Results ---------------    │
│  ┌────────────────────────────────┐  │
│  │  PowerView-001                 │  │
│  │  192.168.1.42 · Port 5555      │  │
│  │                    [Connect]   │  │
│  ├────────────────────────────────┤  │
│  │  PowerView-002                 │  │
│  │  192.168.1.55 · Port 5555      │  │
│  └────────────────────────────────┘  │
│                                      │
│  --- Manual ----------------------   │
│  IP Address: [___________________]   │
│  Port:       [5555_______________]   │
│                                      │
│         [Scan Again]                 │
│         [Connect Manually]           │
└──────────────────────────────────────┘
```

---

## 6. Dashboard Tab

```
┌──────────────────────────────────────┐
│  Dashboard    [Playlist]    [more]   │
├──────────────────────────────────────┤
│                                      │
│  ┌──────────────────────────────┐   │
│  │                              │   │
│  │    Pi Display Mirror         │   │
│  │    (WebView / SVG render)    │   │
│  │                              │   │
│  │    L1: 220V  30A  6.6kW      │   │
│  │    L2: 221V  40A  8.8kW      │   │
│  │    L3: 220V  50A  11.0kW     │   │
│  │    Total: 26.4kW  PF: 0.92   │   │
│  │                              │   │
│  └──────────────────────────────┘   │
│                                      │
│  Playlist: [<] Dashboard 2/3 [>]    │
│  Auto-advance: 00:45                 │
└──────────────────────────────────────┘
```

**Playlist Manager (Bottom Sheet)**

```
┌──────────────────────────────────────┐
│  ───────                             │
│  Playlist  3 dashboards       [+Add] │
├──────────────────────────────────────┤
│  =  Dashboard 1 (Energy)  30s   [x] │
│  =  Dashboard 2 (Power)   20s   [x] │
│  =  Dashboard 3 (Current) 15s   [x] │
├──────────────────────────────────────┤
│  Auto-play  [ toggle ]               │
└──────────────────────────────────────┘
```

> Dashboard แรกเริ่มต้น 1 ใบ ไม่มีปุ่มลบ
> Add เพิ่ม → แสดง timer + ปุ่มลบ (ลบได้เมื่อมีมากกว่า 1)

---

## 7. Live Data Tab

```
┌──────────────────────────────────────┐
│  Live Data   [live]  Updated 2s ago  │
├──────────────────────────────────────┤
│  SUMMARY                             │
│  ┌────────────────────────────────┐  │
│  │  26.4 kW   12.1 kVAR  29.0 kVA│  │
│  │  PF 0.91   50.0 Hz    29°C    │  │
│  └────────────────────────────────┘  │
│                                      │
│  PHASES                              │
│  ┌────────────────────────────────┐  │
│  │        L1     L2     L3        │  │
│  │  V   220.1  220.8  219.6  V   │  │
│  │  A    30.1   40.2   50.3  A   │  │
│  │  kW   6.61   8.84  11.01  kW  │  │
│  │  kVAR 1.21   1.86   2.31 kvar │  │
│  │  kVA  6.72   9.03  11.25  kVA │  │
│  │  PF   0.98   0.98   0.98      │  │
│  │  THD  2.3%   2.5%   2.7%      │  │
│  └────────────────────────────────┘  │
│                                      │
│  ENERGY                              │
│  ┌────────────────────────────────┐  │
│  │  Import     205.79 kWh         │  │
│  │  Reactive    50.82 kVARh       │  │
│  │  Apparent   248.70 kVAh        │  │
│  │  Cost          823.16 บาท      │  │
│  │  Carbon       82.11 kgCO2      │  │
│  │  Since: 15 Jan 2025 08:00      │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

---

## 8. File Structure (Dart)

```
lib/
├── main.dart
└── src/
    ├── app.dart                        MaterialApp, theme, routing
    │
    ├── models/
    │   ├── meter_snapshot.dart         LineData, TotalData, MeterSnapshot
    │   ├── pi_settings.dart            PiNetworkSettings, WifiNetwork,
    │   │                               PiPowerViewSettings (ctType, elecRate, cef)
    │   ├── dashboard_info.dart         DashboardInfo, DashboardList
    │   ├── source_config.dart          SourceConfig
    │   ├── source_list.dart            SourceList
    │   ├── modbus_profile.dart         ModbusProfile
    │   └── modbus_profile_list.dart    ModbusProfileList
    │
    ├── services/
    │   ├── device_client.dart          TCP/USB command wrapper
    │   ├── discovery_service.dart      UDP broadcast discovery (interface)
    │   ├── discovery_service_io.dart   platform: dart:io
    │   ├── discovery_service_stub.dart platform: web stub
    │   └── modbus_profile_catalog.dart loads builtin profiles from assets
    │
    ├── transport/
    │   ├── app_transport.dart          abstract interface
    │   ├── tcp_transport.dart          TCP socket (dispatcher)
    │   ├── tcp_transport_io.dart       platform: dart:io
    │   ├── tcp_transport_stub.dart     platform: web stub
    │   └── usb_transport.dart          USB serial
    │
    ├── protocol/
    │   ├── device_response.dart        parse ":cmd ok {json}" / err
    │   └── power_view_commands.dart    command string constants
    │
    └── ui/
        │
        ├── [NAVIGATION]
        │   home_page.dart              MainPage + NavigationBar/Rail
        │
        ├── [CONNECTION]  (แนะนำแยกออกจาก home_page)
        │   connection_page.dart        REFACTOR: TCP/USB + discovery
        │
        ├── [TAB 0 - DASHBOARD]
        │   monitor_page.dart           Pi display mirror
        │   dashboard_selector_sheet.dart  bottom sheet list
        │   playlist_manager_sheet.dart  PLANNED: add/reorder/timer
        │
        ├── [TAB 1 - LIVE DATA]
        │   meter_data_page.dart        Summary + Phase + Energy
        │
        ├── [TAB 2 - HISTORY]
        │   energy_history_page.dart    PLANNED
        │
        ├── [TAB 3 - SETTINGS]
        │   pi_settings_page.dart       grouped menu list
        │
        │   -- METER group
        │   source_list_view.dart       Sources list
        │   source_editor_dialog.dart   edit Modbus source
        │   meter_type_picker.dart      profile + group chip picker
        │   pi_power_view_page.dart     CT type, electricity rate, carbon factor
        │   pi_meter_actions_page.dart  reset meter
        │   collector_settings_page.dart  PLANNED: CT + modbus slave
        │   alarm_settings_page.dart    PLANNED
        │
        │   -- CONNECTIVITY group
        │   pi_wifi_page.dart
        │   pi_network_page.dart
        │   mqtt_settings_page.dart     PLANNED
        │
        │   -- SYSTEM group
        │   security_page.dart          PLANNED
        │   about_page.dart             PLANNED
        │
        └── [SHARED WIDGETS]
            pi_settings_widgets.dart    PiCard, PiField, PiDivider, PiErrorView
            pi_config_tree.dart         config tree viewer (debug)
```

---

## 9. Communication Protocol

### Command Format (ใหม่)

```
App --> Pi    :command [args]
Pi  --> App   :command ok {"key": "value"}
Pi  --> App   :command err {"code": "...", "message": "..."}
```

### Legacy Format (command เก่า)

```
App --> Pi    :command
Pi  --> App   :command value
```

### Key Commands

| Command | Description |
|---------|-------------|
| `:meter_snapshot` | อ่าน V/I/P/E ทุก phase พร้อมกัน (JSON) |
| `:dashboard_list` | รายชื่อ dashboard + index ปัจจุบัน |
| `:dashboard_set <i>` | สั่ง Pi แสดง dashboard ที่ i |
| `:source_list` | รายการ Modbus sources |
| `:source_add <json>` | เพิ่ม source |
| `:source_update <id> <json>` | แก้ไข source |
| `:source_remove <id>` | ลบ source |
| `:source_set_active <id>` | เลือก active source |
| `:modbus_profile_list` | รายชื่อ profiles ทั้งหมด |
| `:ipaddr` | อ่าน IP ปัจจุบัน |
| `:dhcp` | สถานะ DHCP on/off |
| `:ssid` | WiFi ที่เชื่อมต่ออยู่ |
| `:ssid_ls` | สแกน WiFi รอบข้าง |
| `:pvget_ct_type` | CT type (0-3) |
| `:pvset_ct_type <n>` | ตั้ง CT type |
| `:pvget_elec_rate` | ค่าไฟ บาท/kWh |
| `:pvset_elec_rate <v>` | ตั้งค่าไฟ |
| `:pvget_cef` | carbon factor kgCO2/kWh |
| `:pvset_cef <v>` | ตั้ง carbon factor |
| `:pv_reset_meter` | reset Wh counter |

### UDP Discovery

```
App broadcast --> 255.255.255.255:30303   "PVIEW_DISCOVER"
Pi unicast    --> App IP:30303            "PVIEW_HERE <device_name> <tcp_port>"
```

---

## 10. State & Data Flow

```
DeviceClient  (1 instance per connection session)
      │
      ├── TCP / USB Transport
      │
      ├── getMeterSnapshot()   --> MeterSnapshot model
      │        poll 1s
      │   MeterDataPage (StatefulWidget) re-renders
      │
      ├── getNetworkSettings() --> PiNetworkSettings model
      │
      ├── getDashboardList()   --> DashboardList model
      │        on change
      │   DashboardSelectorSheet re-renders
      │
      └── getWifiList()        --> List<WifiNetwork>
```

> ปัจจุบัน state management = **StatefulWidget + setState**
> อนาคต: พิจารณา Riverpod เมื่อ feature เพิ่มขึ้นและ state ซับซ้อนขึ้น

---

## 11. Asset Files

```
assets/
└── modbus_profiles_builtin.json    Builtin Modbus register maps
    ├── schneider_pm5000            Groups A/B/C (PM5100-PM8000/iEM/PM2000)
    ├── abb_m2m                     Groups A/B/C (M4M/M1M/A43-A44/M2M/DMTME)
    ├── siemens_pac3200             PAC3100 / Group A (PAC3200/3220)
    ├── chint_ddsu666               Single phase
    └── sdm630                      Eastron SDM630
```

---

## 12. Shared Widgets (pi_settings_widgets.dart)

| Widget | Usage |
|--------|-------|
| `PiCard` | Card wrapper พร้อม optional section label |
| `PiField` | TextField พร้อม lock icon เมื่อ readOnly (DHCP) |
| `PiDivider` | Divider บางภายใน card |
| `PiErrorView` | Error state + retry button |

---

## 13. AppBar Design (persistent)

```
┌──────────────────────────────────────────┐
│  [=]   PowerView-001   [bell]  [more]    │
│         192.168.1.42                      │
└──────────────────────────────────────────┘
```

- **[=]** hamburger (future: drawer)
- **device name** + IP จาก discovery หรือ manual entry
- **[bell]** alarm indicator (กระดิ่งสั่นเมื่อมี alarm event) - PLANNED
- **[more]** overflow:
  - View Log
  - Disconnect
  - Reconnect

---

## 14. Phone vs Tablet Layout

**Phone (< 600dp width)**
```
┌──────────────────┐
│   AppBar         │
├──────────────────┤
│                  │
│   Active Tab     │
│   Content        │
│                  │
├──────────────────┤
│  [D][L][H][S]    │  NavigationBar
└──────────────────┘
```

**Tablet / Desktop (>= 600dp width)**
```
┌────┬─────────────────────────────┐
│    │ AppBar                      │
│ D  ├─────────────────────────────┤
│ L  │                             │
│ H  │   Active Tab Content        │
│ S  │                             │
│    │                             │
└────┴─────────────────────────────┘
NavigationRail
```

---

## 15. Feature Roadmap

| Feature | Status | Notes |
|---------|--------|-------|
| TCP discovery (UDP) | Done | single-socket broadcast |
| USB connection | Done | |
| Dashboard mirror | Done | SVG + WebView |
| Playlist manager | Planned | timer per dashboard, drag sort |
| Live data display | Done | |
| Energy history chart | Planned | line/bar + date range |
| Alarm settings | Planned | V>/V<, A>/A< per phase |
| MQTT settings | Planned | broker, topic, data select, interval |
| Security (user/pass) | Planned | |
| Firmware update OTA | Planned | |
| About / Info page | Partial | reads version/SN from `:info 99`, falls back to legacy commands |
| Modbus Slave config | Planned | Pi acts as Modbus slave |
| ABB Group A/B/C | Done | updated from abb modbus.csv |
| Schneider Groups A/B/C | Done | fixed voltage + power ordering |
| Siemens PAC3100/3200 | Done | two sources |

---

*Last updated: 2026-05-21*
