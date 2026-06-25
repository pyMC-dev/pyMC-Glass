# Repeater handoff: Sensor telemetry for Glass

_Last checked against Repeater commit `c0d919c` (`rightup/pyMC_Repeater` `origin/dev`, fetched 2026-06-24)._

## Current status

openHop Glass is ready to accept a top-level `/inform` field named `sensors` and render it on the repeater detail page as “Sensor Readings”.

The current Repeater branch already has:

- `SensorManager.get_summary()` in `repeater/sensors/manager.py`
- sensor subsystem config under `sensors` in `config.yaml.example`
- `RepeaterDaemon.get_stats()` adding `stats["sensors"] = sensor_manager.get_summary()`
- sensor plugins including `waveshare_ups_d`, `waveshare_ups_e`, `lafvin_ups_3s`, `ina219`, `ens210`, `hardware_stats`, and `pymc_modem`

The current Repeater branch does **not** yet include `sensors` in the Glass `/inform` payload built by `repeater/data_acquisition/glass_handler.py`. As of commit `c0d919c`, `_build_inform_payload()` returns `type`, `version`, identity, system/radio/counter fields, `settings`, and `command_results`, but not `sensors`.

So the remaining Repeater-side work is to attach the existing `SensorManager.get_summary()` output to the Glass inform payload.

## Current Glass contract

Glass `/inform` accepts this optional top-level field:

```json
{
  "type": "inform",
  "version": 1,
  "node_name": "repeater-1",
  "pubkey": "0x...",
  "software_version": "1.0.10",
  "state": "forward",
  "uptime_seconds": 123,
  "config_hash": "sha256:<64-hex-chars>",
  "system": { "cpu_percent": 10, "memory_percent": 20, "disk_percent": 30 },
  "radio": { "frequency": 869618000, "spreading_factor": 8, "bandwidth": 62500, "tx_power": 14 },
  "counters": { "rx_total": 0, "tx_total": 0, "forwarded": 0, "dropped": 0, "duplicates": 0, "airtime_percent": 0 },
  "settings": {},
  "sensors": {
    "enabled": true,
    "poll_interval_seconds": 30,
    "configured": 2,
    "loaded": 2,
    "running": true,
    "readings": [
      {
        "name": "ups-main",
        "type": "waveshare_ups_d",
        "ok": true,
        "timestamp": "2026-06-20T12:00:00+00:00",
        "data": {
          "battery_percent": 87.5,
          "bus_voltage_v": 4.08,
          "shunt_voltage_mv": 1.25,
          "current_ma": 120.0,
          "power_mw": 490.0,
          "charge_state": "discharging"
        }
      }
    ]
  },
  "command_results": []
}
```

Glass stores this in the latest inform snapshot/system detail and the frontend reads it from `detail.system.sensors`.

## Required Repeater change

In `repeater/data_acquisition/glass_handler.py`, update `GlassHandler._build_inform_payload()`.

Suggested implementation:

```python
sensors_summary = None
sensor_manager = getattr(self.daemon_instance, "sensor_manager", None)
if sensor_manager is not None:
    try:
        sensors_summary = sensor_manager.get_summary()
    except Exception as exc:
        logger.debug("Failed collecting sensor summary for Glass inform: %s", exc)
        sensors_summary = {
            "enabled": False,
            "configured": 0,
            "loaded": 0,
            "running": False,
            "readings": [],
            "error": str(exc),
        }

payload = {
    ...existing inform fields...,
    "settings": settings_snapshot,
    "command_results": command_results,
}
if sensors_summary is not None:
    payload["sensors"] = sensors_summary
return payload
```

Prefer omitting `sensors` when no `sensor_manager` exists. If a manager exists but raises, include the error summary above so Glass can show that sensor collection failed without breaking the inform loop.

## Preferred payload shape

Use the current Repeater `SensorManager.get_summary()` shape directly:

```json
{
  "enabled": true,
  "poll_interval_seconds": 30.0,
  "configured": 2,
  "loaded": 2,
  "running": true,
  "readings": [
    {
      "name": "sensor-name",
      "type": "sensor-type",
      "ok": true,
      "timestamp": "RFC3339 timestamp",
      "data": {}
    }
  ]
}
```

Keep values JSON-safe:

- numbers as JSON numbers
- booleans as booleans
- strings as strings
- arrays/objects only when serializable
- no bytes objects
- no secrets

## UPS and battery field names in current Repeater

Glass renders unknown sensor fields generically, so it does not require a fixed UPS schema. However, current Repeater sensors already use these keys and future first-class gauges should prefer them:

Common:

- `battery_percent`
- `current_ma`
- `charge_state` (`charging`, `discharging`, `idle`, etc.)

`waveshare_ups_d` / `lafvin_ups_3s`:

- `bus_voltage_v`
- `shunt_voltage_mv`
- `current_ma`
- `power_mw`
- `battery_percent`
- `charge_state`

`waveshare_ups_e`:

- `charge_state`
- `battery_voltage_mv`
- `battery_current_ma`
- `battery_percent`
- `remaining_capacity_mah`
- `vbus_voltage_mv`
- `vbus_current_ma`
- `vbus_power_mw`
- `cell_voltages_mv`

`pymc_modem` sensor:

- passes through battery and modem stats such as `battery_voltage_mv`, `battery_voltage_v`, `battery_percent`, `battery_percentage`, and `solar_charge_rate_percent_per_hour` when present
- computes `battery_percent` from single-cell voltage if the modem payload exposes voltage but not percent

Avoid inventing new names like `power_w` or `charging` in Repeater unless the sensor really emits them. If adding normalized fields later, keep the existing fields for compatibility.

## MQTT event telemetry option

Glass already stores arbitrary MQTT event telemetry in `mqtt_ingest_events`.

If Repeater later wants higher-rate sensor telemetry over MQTT, publish an event envelope via the existing Glass MQTT publisher:

```python
glass_handler.publish_telemetry("sensors", sensor_manager.get_summary())
```

That publishes to a topic like:

```text
glass/<node_name>/event/sensors
```

Payload should use the same `SensorManager.get_summary()` shape.

Recommended approach:

- `/inform` carries the latest sensor summary for inventory/detail pages.
- MQTT `event/sensors` can carry higher-frequency readings later.
- Keep `/inform` bounded and avoid dumping high-volume sensor history into it.

## Tests to add in Repeater

Add tests around `GlassHandler._build_inform_payload()`:

1. Includes top-level `sensors` when `daemon_instance.sensor_manager` exists.
2. Omits `sensors` when no sensor manager exists.
3. If `sensor_manager.get_summary()` raises, inform still succeeds and includes a useful error summary or intentionally omits `sensors`.
4. A `waveshare_ups_d`, `waveshare_ups_e`, `lafvin_ups_3s`, and `pymc_modem` reading remains JSON serializable.
5. Existing `command_results` behavior is unchanged.
6. Optional: MQTT publishing of `record_type="sensors"` produces `type="event"` and `event_name="sensors"`.

## Acceptance check

After Repeater implementation:

1. Enable at least one Repeater sensor in `config.yaml`.
2. Confirm Repeater `/api/stats` includes `sensors` from `daemon.get_stats()`.
3. Confirm Repeater Glass `/inform` payload includes top-level `sensors`.
4. Confirm Glass accepts `/inform` without contract errors.
5. In Glass, open the repeater detail page.
6. Confirm the “Sensor Readings” section shows each reading and data value.
7. Confirm a sensor exception does not break the Glass inform loop.
