import AppearanceSection from "@/features/settings/AppearanceSection";
import ModelSection from "@/features/settings/ModelSection";

export default function SettingsPage() {
  return (
    <main className="mx-auto max-w-3xl space-y-6 p-6">
      <h1 className="text-2xl font-bold text-foreground">Settings</h1>
      <AppearanceSection />
      <ModelSection />
    </main>
  );
}
