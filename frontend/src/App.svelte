<script lang="ts">
  import { onMount } from "svelte";

  type Phase = "preview" | "ready" | "installing" | "complete" | "error";
  import type { InstallStatus } from "./wails";
  let status = $state<InstallStatus>({
    phase: "preview", version: "", message: "Waiting for the Windows installer service.",
  });
  let starting = $state(false);
  let displayError = $state("");

  async function refresh() {
    const bridge = window.go?.main?.App;
    if (!bridge) {
      status = { phase: "preview", version: "", message: "Browser preview only. Launch through Wails to enable installation." };
      return;
    }
    try { status = await bridge.GetStatus(); }
    catch (error) { displayError = String(error); }
  }
  async function startInstall() {
    const bridge = window.go?.main?.App;
    if (!bridge || starting || status.phase !== "ready") return;
    starting = true;
    displayError = "";
    try { await bridge.BeginInstall(); await refresh(); }
    catch (error) { displayError = String(error); }
    finally { starting = false; }
  }
  onMount(() => {
    void refresh();
    const timer = window.setInterval(() => { void refresh(); }, 550);
    return () => window.clearInterval(timer);
  });
</script>

<svelte:head>
  <title>Paglora · Windows Installer</title>
</svelte:head>

<div class="app">
  <aside class="rail">
    <div class="brand"><span class="brand-mark">P</span> Paglora</div>
    <div class="stage-list" aria-label="Installation steps">
      <div class:active={status.phase === "ready" || status.phase === "preview" || status.phase === "error"} class="stage">
        <span class="stage-number">1</span><span>Get ready</span>
      </div>
      <div class:active={status.phase === "installing"} class="stage">
        <span class="stage-number">2</span><span>Install</span>
      </div>
      <div class:active={status.phase === "complete"} class="stage">
        <span class="stage-number">3</span><span>Finished</span>
      </div>
    </div>
    <div class="rail-bottom">Windows installer<br />Local-first documentation studio<br />No sign-in required</div>
  </aside>
  <main class="content">
    <p class="eyebrow">Paglora · Desktop setup</p>
    {#if status.phase === "complete"}
      <h1>You're all set.</h1>
      <p class="lead">Paglora has finished installing. Your documentation stays on your own computer.</p>
      <div class="info"><div class="detail"><span>Installation</span><strong class="success">Completed</strong></div>
      <div class="detail"><span>What's next?</span><strong>Open Paglora from Start</strong></div></div>
    {:else if status.phase === "installing"}
      <h1>Installing Paglora.</h1>
      <p class="lead">The official Windows setup is installing the application. Please keep this window open.</p>
      <div class="progress" role="progressbar" aria-label="Installing Paglora" aria-valuetext="In progress"></div>
      <p class="notice" aria-live="polite">{status.message}</p>
    {:else}
      <h1>Make space for ideas.</h1>
      <p class="lead">Beautiful documentation, built locally. Install Paglora Studio and start creating without accounts or subscriptions.</p>
      <div class="info">
        <div class="detail"><span>Application</span><strong>Paglora Studio</strong></div>
        <div class="detail"><span>Version</span><strong>{status.version || "Development preview"}</strong></div>
        <div class="detail"><span>Installation</span><strong>Current Windows user</strong></div>
        <div class="detail"><span>Installer source</span><strong><span class="pill">Bundled Tauri NSIS</span></strong></div>
      </div>
      {#if status.phase === "preview"}
        <p class="notice">Preview mode: {status.message} The Install button is unavailable until an official verified Paglora NSIS package is bundled.</p>
      {:else if status.phase === "error"}
        <p class="notice error" role="alert">{status.message}</p>
      {:else}
        <p class="notice">{status.message} Setup will not intentionally overwrite your local documentation projects.</p>
      {/if}
    {/if}
    {#if displayError}<p class="notice error" role="alert">{displayError}</p>{/if}
    <div class="actions">
      <span class="small-note">© Paglora · Built by m1nsook</span>
      {#if status.phase === "ready"}
        <button class="primary" onclick={startInstall} disabled={starting}>Install Paglora</button>
      {:else if status.phase === "installing"}
        <button class="primary" disabled>Installing…</button>
      {:else if status.phase === "complete"}
        <span class="pill">Setup complete</span>
      {:else}
        <button class="primary" disabled>Install unavailable</button>
      {/if}
    </div>
  </main>
</div>
