<script setup lang="ts">
import { useTheme } from "../composables/useTheme";

const { theme, toggleTheme } = useTheme();
</script>

<template>
  <button
    class="theme-toggle"
    :aria-label="theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'"
    :title="theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'"
    @click="toggleTheme"
  >
    <!-- Sun icon (visible in dark mode) -->
    <svg
      v-if="theme === 'dark'"
      xmlns="http://www.w3.org/2000/svg"
      class="theme-toggle-icon sun-icon"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      stroke-width="2"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"
      />
    </svg>

    <!-- Moon icon (visible in light mode) -->
    <svg
      v-else
      xmlns="http://www.w3.org/2000/svg"
      class="theme-toggle-icon moon-icon"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      stroke-width="2"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z"
      />
    </svg>
  </button>
</template>

<style scoped>
.theme-toggle {
  align-items: center;
  background: var(--color-background-mute);
  border: 1px solid var(--color-border-subtle);
  border-radius: 0.5rem;
  color: var(--color-text-secondary);
  cursor: pointer;
  display: flex;
  height: 35px;
  justify-content: center;
  transition:
    background-color 0.2s ease,
    border-color 0.2s ease,
    color 0.2s ease;
  width: 35px;
}

.theme-toggle:hover {
  background: var(--color-theme-toggle-hover);
  border-color: var(--color-border);
}

.theme-toggle-icon {
  height: 1.25rem;
  width: 1.25rem;
}

.sun-icon {
  color: #facc15;
}

.moon-icon {
  color: var(--color-text-secondary);
}
</style>
