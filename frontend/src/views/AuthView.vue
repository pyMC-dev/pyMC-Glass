<template>
  <main class="auth-page">
    <UiPanelCard class="auth-card">
      <header>
        <div class="auth-brand">
          <img class="auth-logo" :src="logoImage" alt="openHop Glass logo" />
          <h1 class="auth-product-title">Glass</h1>
          <p class="auth-product-subtitle">Mesh network orchestration</p>
        </div>
      </header>

      <p v-if="appState.initializing" class="notice">Checking system bootstrap state…</p>

      <template v-else>
        <form
          v-if="appState.needsBootstrap"
          class="auth-form"
          @submit.prevent="handleBootstrap"
        >
          <h2>Initialize Admin Account</h2>
          <p class="section-subtitle">
            The system requires one bootstrap administrator before first login.
          </p>
          <label class="field-label">
            Email
            <input v-model.trim="bootstrapForm.email" class="field" type="email" required />
          </label>
          <label class="field-label">
            Display name
            <input v-model.trim="bootstrapForm.display_name" class="field" type="text" />
          </label>
          <label class="field-label">
            Password
            <input v-model="bootstrapForm.password" class="field" type="password" minlength="10" required />
          </label>
          <button class="btn btn-primary" :disabled="appState.bootstrapLoading">
            {{ appState.bootstrapLoading ? "Creating..." : "Create Admin" }}
          </button>
        </form>

        <form class="auth-form" @submit.prevent="handleLogin">
          <h2>Sign in</h2>
          <label class="field-label">
            Email
            <input v-model.trim="loginForm.email" class="field" type="email" required />
          </label>
          <label class="field-label">
            Password
            <input v-model="loginForm.password" class="field" type="password" required />
          </label>
          <button
            class="btn btn-primary"
            :disabled="appState.loginLoading || appState.needsBootstrap"
          >
            {{ appState.loginLoading ? "Signing in..." : "Sign in" }}
          </button>
          <p v-if="appState.needsBootstrap" class="section-subtitle">
            Login is disabled until bootstrap admin setup is completed.
          </p>
        </form>
      </template>
    </UiPanelCard>

    <p v-if="appState.toastError" class="toast toast-error">{{ appState.toastError }}</p>
    <p v-if="appState.toastSuccess" class="toast toast-success">{{ appState.toastSuccess }}</p>
  </main>
</template>

<script setup lang="ts">
import { reactive } from "vue";
import { useRouter } from "vue-router";
import UiPanelCard from "../components/ui/UiPanelCard.vue";
import logoImage from "../assets/logo/openhop_transparent_trim.png";

import { appState, bootstrapAdminAccount, loginAccount } from "../state/appState";

const router = useRouter();

const bootstrapForm = reactive({
  email: "",
  password: "",
  display_name: "",
});

const loginForm = reactive({
  email: "",
  password: "",
});

async function handleBootstrap(): Promise<void> {
  try {
    await bootstrapAdminAccount({
      email: bootstrapForm.email,
      password: bootstrapForm.password,
      display_name: bootstrapForm.display_name || undefined,
    });
    loginForm.email = bootstrapForm.email;
    bootstrapForm.password = "";
  } catch {
    // Error already surfaced via global toast.
  }
}

async function handleLogin(): Promise<void> {
  try {
    await loginAccount(loginForm.email, loginForm.password);
    await router.replace("/dashboard");
  } catch {
    // Error already surfaced via global toast.
  }
}
</script>

<style scoped>
.auth-page {
  min-height: 100vh;
  display: grid;
  place-items: center;
  padding: 1rem;
}

.auth-card {
  width: min(540px, 100%);
  padding: 1.15rem;
  display: grid;
  gap: 1rem;
}

.auth-brand {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  width: 100%;
}

.auth-logo {
  display: block;
  width: min(300px, 64vw);
  max-width: 100%;
  height: auto;
  padding: 0.85rem;
  border: 1px solid rgba(148, 163, 184, 0.28);
  border-radius: 1rem;
  background: radial-gradient(circle at 30% 20%, rgba(96, 165, 250, 0.16), transparent 42%),
    linear-gradient(145deg, #020617, #0f172a 58%, #111827);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.08), 0 18px 45px rgba(15, 23, 42, 0.16);
}

.auth-product-title {
  margin-top: 0.2rem;
  color: var(--color-text-primary);
  font-size: clamp(1.35rem, 4vw, 1.8rem);
  font-weight: 800;
  letter-spacing: 0.02em;
  line-height: 1;
}

.auth-product-subtitle {
  margin-top: 0.45rem;
  color: var(--color-text-muted);
  font-size: 0.82rem;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.auth-form {
  display: grid;
  gap: 0.75rem;
  padding: 0.85rem;
  border-radius: 12px;
  border: 1px solid var(--color-border-subtle);
  background: rgba(255, 255, 255, 0.02);
}

.auth-form h2 {
  font-size: 1.03rem;
}

.notice {
  color: var(--color-accent-amber);
}
</style>
