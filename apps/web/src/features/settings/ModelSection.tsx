import { useEffect, useState } from "react";
import { useAction, useMutation, useQuery } from "convex/react";
import { toast } from "sonner";
import { api } from "../../../convex/_generated/api";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import ModelComparison, { type ModelRow } from "@/features/settings/ModelComparison";
import { DEFAULT_MODEL } from "../../../convex/models.shared";

export default function ModelSection() {
  const listModels = useAction(api.settings.listModels);
  const setModel = useMutation(api.settings.setModel);
  const settings = useQuery(api.settings.getSettings);
  const selectedId = settings?.modelId ?? DEFAULT_MODEL;

  const [models, setModels] = useState<ModelRow[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    listModels({})
      .then((rows) => {
        if (!cancelled) setModels(rows as ModelRow[]);
      })
      .catch((e) => {
        if (!cancelled) {
          toast.error(e instanceof Error ? e.message : "Failed to load models");
          setModels([]);
        }
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function handleSelect(modelId: string) {
    try {
      await setModel({ modelId });
      const name = models?.find((m) => m.id === modelId)?.name ?? modelId;
      toast.success(`Model set to ${name}`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to update model");
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Model</CardTitle>
        <CardDescription>
          Compare cost and quality, then choose which model powers chat.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {models === null ? (
          <div className="space-y-3">
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </div>
        ) : (
          <ModelComparison models={models} selectedId={selectedId} onSelect={(id) => void handleSelect(id)} />
        )}
      </CardContent>
    </Card>
  );
}
