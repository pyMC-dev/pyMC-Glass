<template>
  <section class="page-grid">
    <header class="page-header">
      <div>
        <h1 class="section-title">Repeater Map</h1>
        <p class="section-subtitle">
          Location-based network visibility. Location format expected: <code>lat,lng</code>.
        </p>
      </div>
      <button class="btn btn-secondary" :disabled="appState.dataLoading" @click="refreshAllData()">
        {{ appState.dataLoading ? "Refreshing..." : "Refresh map data" }}
      </button>
    </header>

    <section class="grid-3">
      <UiStatCard title="Total Repeaters" :value="appState.repeaters.length" />
      <UiStatCard title="Mapped (coords)" :value="mappedRepeaters.length" />
      <UiStatCard title="Missing Coordinates" :value="unmappedRepeaters.length" />
    </section>

    <article class="glass-card panel">
      <h2>Geospatial Plot</h2>
      <p v-if="mappedRepeaters.length === 0" class="section-subtitle">
        No parseable coordinates. Set repeater location as <code>lat,lng</code> (example: <code>51.5074,-0.1278</code>).
      </p>
      <div v-else ref="mapElement" class="leaflet-map" aria-label="Repeater map"></div>
    </article>

    <section class="grid-2">
      <article class="glass-card panel">
        <h2>Mapped Repeaters</h2>
        <UiDataTable>
          <thead>
            <tr>
              <th>Node</th>
              <th>Coordinates</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="item in mappedRepeaters" :key="item.id">
              <td>{{ item.node_name }}</td>
              <td><code>{{ item.location }}</code></td>
              <td><StatusPill :status="item.status" /></td>
            </tr>
            <tr v-if="mappedRepeaters.length === 0">
              <td colspan="3" class="section-subtitle">No mapped repeaters.</td>
            </tr>
          </tbody>
        </UiDataTable>
      </article>

      <article class="glass-card panel">
        <h2>Repeaters Missing Coordinates</h2>
        <UiDataTable>
          <thead>
            <tr>
              <th>Node</th>
              <th>Location Field</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="item in unmappedRepeaters" :key="item.id">
              <td>{{ item.node_name }}</td>
              <td>{{ item.location || "—" }}</td>
              <td><StatusPill :status="item.status" /></td>
            </tr>
            <tr v-if="unmappedRepeaters.length === 0">
              <td colspan="3" class="section-subtitle">All repeaters include coordinates.</td>
            </tr>
          </tbody>
        </UiDataTable>
      </article>
    </section>
  </section>
</template>

<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import UiDataTable from "../components/ui/UiDataTable.vue";
import UiStatCard from "../components/ui/UiStatCard.vue";

import StatusPill from "../components/ui/StatusPill.vue";
import { useTheme } from "../composables/useTheme";
import { appState, refreshAllData } from "../state/appState";

interface MapPoint {
  id: string;
  node_name: string;
  location: string;
  status: string;
  lat: number;
  lng: number;
}

const mapElement = ref<HTMLElement | null>(null);
const { theme } = useTheme();
let map: L.Map | null = null;
let markerLayer: L.LayerGroup | null = null;
let tileLayer: L.TileLayer | null = null;

function parseCoords(location: string | null): { lat: number; lng: number } | null {
  if (!location) {
    return null;
  }

  const trimmed = location.trim();
  if (!trimmed) {
    return null;
  }

  try {
    if (trimmed.startsWith("{")) {
      const parsed = JSON.parse(trimmed) as Record<string, unknown>;
      return parseCoordsFromObject(parsed);
    }
  } catch {
    // Fall through to string parsing.
  }

  const directParts = trimmed
    .replace(";", ",")
    .split(",")
    .map((part) => Number.parseFloat(part.trim()))
    .filter((value) => !Number.isNaN(value));
  if (directParts.length >= 2) {
    return normalizeCoords(directParts[0], directParts[1]);
  }

  const numbers = trimmed.match(/[-+]?\d*\.?\d+/g);
  if (!numbers || numbers.length < 2) {
    return null;
  }
  const lat = Number.parseFloat(numbers[0]);
  const lng = Number.parseFloat(numbers[1]);
  return normalizeCoords(lat, lng);
}

function parseCoordsFromObject(value: Record<string, unknown>): { lat: number; lng: number } | null {
  const latRaw = value.lat ?? value.latitude;
  const lngRaw = value.lng ?? value.lon ?? value.longitude;
  const lat = Number.parseFloat(String(latRaw));
  const lng = Number.parseFloat(String(lngRaw));
  return normalizeCoords(lat, lng);
}

function normalizeCoords(lat: number, lng: number): { lat: number; lng: number } | null {
  if (Number.isNaN(lat) || Number.isNaN(lng)) {
    return null;
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return null;
  }
  return { lat, lng };
}

const mappedRepeaters = computed<MapPoint[]>(() =>
  appState.repeaters
    .map((repeater) => {
      const coords = parseCoords(repeater.location);
      if (!coords || !repeater.location) {
        return null;
      }
      return {
        id: repeater.id,
        node_name: repeater.node_name,
        location: repeater.location,
        status: repeater.status,
        lat: coords.lat,
        lng: coords.lng,
      };
    })
    .filter((value): value is MapPoint => Boolean(value)),
);

const unmappedRepeaters = computed(() =>
  appState.repeaters.filter((repeater) => parseCoords(repeater.location) === null),
);

onMounted(async () => {
  if (appState.token) {
    await refreshAllData();
  }
  await nextTick();
  renderMap();
});

onBeforeUnmount(() => {
  if (map) {
    map.remove();
    map = null;
    markerLayer = null;
    tileLayer = null;
  }
});

watch(mappedRepeaters, () => {
  void nextTick().then(renderMap);
});

watch(theme, () => {
  updateTileLayer();
});

function mapTileUrl(): string {
  return "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png";
}

function updateTileLayer(): void {
  if (!map) return;
  if (tileLayer) {
    tileLayer.removeFrom(map);
    tileLayer = null;
  }
  tileLayer = L.tileLayer(mapTileUrl(), {
    maxZoom: 19,
    crossOrigin: true,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
  }).addTo(map);
}

function renderMap(): void {
  if (!mapElement.value || mappedRepeaters.value.length === 0) {
    return;
  }

  if (!map) {
    map = L.map(mapElement.value, {
      worldCopyJump: true,
      zoomControl: true,
    });
    updateTileLayer();
    markerLayer = L.layerGroup().addTo(map);
  }

  markerLayer?.clearLayers();
  const bounds = L.latLngBounds([]);
  for (const item of mappedRepeaters.value) {
    const marker = L.circleMarker([item.lat, item.lng], {
      radius: 8,
      color: "#dce8ff",
      weight: 1.4,
      fillColor: statusColor(item.status),
      fillOpacity: 0.9,
    }).bindPopup(`<strong>${escapeHtml(item.node_name)}</strong><br>${escapeHtml(item.location)}<br>${escapeHtml(item.status)}`);
    marker.addTo(markerLayer as L.LayerGroup);
    bounds.extend([item.lat, item.lng]);
  }

  if (bounds.isValid()) {
    map.fitBounds(bounds.pad(0.25), { maxZoom: 12 });
  }
  map.invalidateSize();
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>'"]/g, (char) => {
    const entities: Record<string, string> = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      "'": "&#39;",
      '"': "&quot;",
    };
    return entities[char] ?? char;
  });
}

function statusColor(status: string): string {
  if (["adopted", "connected", "success"].includes(status)) {
    return "#56d88a";
  }
  if (["pending_adoption", "queued", "in_progress"].includes(status)) {
    return "#f5c159";
  }
  if (["failed", "rejected", "offline"].includes(status)) {
    return "#f08095";
  }
  return "#9fb2cf";
}
</script>

<style scoped>

.leaflet-map {
  width: 100%;
  min-height: 420px;
  border: 1px solid rgba(130, 160, 210, 0.22);
  border-radius: 16px;
  overflow: hidden;
}
</style>
