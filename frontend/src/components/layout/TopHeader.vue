<template>
  <header class="glass-card sticky top-2 z-40 flex flex-col items-stretch justify-between gap-3 px-4 py-3 sm:top-4 lg:flex-row lg:items-center">
    <div class="flex items-center gap-3">
      <button class="btn btn-ghost inline-flex xl:hidden" @click="$emit('toggle-menu')">☰</button>
      <div class="header-brand" aria-label="openHop Glass">
        <img class="header-brand-logo" :src="logoImage" alt="" aria-hidden="true" />
        <div class="header-brand-copy">
          <span class="header-brand-name">openHop</span>
          <span class="header-brand-product">Glass</span>
        </div>
      </div>
      <div>
        <h2 class="text-base font-semibold text-content-primary">Network Operations</h2>
        <p class="text-xs text-content-muted">
          {{ appState.user?.display_name || appState.user?.email }} · role:
          {{ appState.user?.role }}
        </p>
      </div>
    </div>
    <div class="flex flex-wrap items-center justify-end gap-2">
      <div class="hidden min-w-[220px] text-xs text-content-muted lg:grid">
        <span>API: {{ apiBaseLabel }}</span>
        <span>Last sync: {{ formatTimestamp(appState.lastSyncAt) }}</span>
      </div>
      <button class="btn btn-secondary" :disabled="appState.dataLoading" @click="refreshAllData()">
        {{ appState.dataLoading ? "Refreshing..." : "Refresh" }}
      </button>
      <ThemeToggle />
      <button class="btn btn-danger" @click="logoutAccount">Logout</button>
    </div>
  </header>
</template>

<script setup lang="ts">
import { getApiBaseUrl } from "../../api";
import logoImage from "../../assets/logo/openhop_transparent_trim.png";
import ThemeToggle from "../ThemeToggle.vue";
import { appState, formatTimestamp, logoutAccount, refreshAllData } from "../../state/appState";

const apiBaseLabel = getApiBaseUrl();

defineEmits<{ (e: "toggle-menu"): void }>();
</script>

<style scoped>
.header-brand {
  display: inline-flex;
  align-items: center;
  gap: 0.55rem;
  border-right: 1px solid var(--color-border-subtle);
  padding-right: 0.85rem;
}

.header-brand-logo {
  width: 58px;
  height: 42px;
  object-fit: contain;
  border: 1px solid rgba(148, 163, 184, 0.24);
  border-radius: 0.7rem;
  background: radial-gradient(circle at 25% 20%, rgba(96, 165, 250, 0.16), transparent 46%),
    linear-gradient(145deg, #020617, #0f172a 58%, #111827);
  padding: 0.25rem;
}

.header-brand-copy {
  display: grid;
  gap: 0.02rem;
  line-height: 1;
}

.header-brand-name {
  color: var(--color-text-primary);
  font-size: 0.86rem;
  font-weight: 700;
  letter-spacing: -0.01em;
}

.header-brand-product {
  color: var(--color-text-primary);
  font-size: 1.05rem;
  font-weight: 850;
  letter-spacing: 0.02em;
}

@media (max-width: 640px) {
  .header-brand-copy {
    display: none;
  }

  .header-brand {
    padding-right: 0.55rem;
  }
}
</style>
