import { ref, watch } from "vue";

export type Theme = "light" | "dark";

const STORAGE_KEY = "theme-preference";
const theme = ref<Theme>("dark");
const isInitialized = ref(false);

function applyTheme(newTheme: Theme): void {
  const html = document.documentElement;

  if (newTheme === "dark") {
    html.classList.add("dark");
  } else {
    html.classList.remove("dark");
  }
}

function initTheme(): void {
  if (isInitialized.value) return;

  const stored = localStorage.getItem(STORAGE_KEY) as Theme | null;

  if (stored && (stored === "light" || stored === "dark")) {
    theme.value = stored;
  } else if (window.matchMedia("(prefers-color-scheme: light)").matches) {
    theme.value = "light";
  } else {
    theme.value = "dark";
  }

  applyTheme(theme.value);
  isInitialized.value = true;
}

if (typeof window !== "undefined") {
  initTheme();
}

watch(theme, (newTheme) => {
  localStorage.setItem(STORAGE_KEY, newTheme);
  applyTheme(newTheme);
});

export function useTheme() {
  const toggleTheme = (): void => {
    theme.value = theme.value === "dark" ? "light" : "dark";
  };

  const setTheme = (newTheme: Theme): void => {
    theme.value = newTheme;
  };

  const isDark = (): boolean => theme.value === "dark";

  return {
    theme,
    toggleTheme,
    setTheme,
    isDark,
  };
}
