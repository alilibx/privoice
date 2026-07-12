import PageHeader from "@/components/layout/PageHeader";
import AppearanceSection from "@/features/settings/AppearanceSection";
import ModelSection from "@/features/settings/ModelSection";

export default function SettingsPage() {
  return (
    <div className="flex h-full flex-col">
      <PageHeader title="Settings" />
      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-3xl space-y-6 p-4 sm:p-6">
          <AppearanceSection />
          <ModelSection />
        </div>
      </div>
    </div>
  );
}
