export type Phase = "preview" | "ready" | "installing" | "complete" | "error";
export interface InstallStatus { phase: Phase; version: string; message: string }
declare global {
  interface Window {
    go?: { main?: { App?: {
      GetStatus: () => Promise<InstallStatus>;
      BeginInstall: () => Promise<boolean>;
    } } };
  }
}
