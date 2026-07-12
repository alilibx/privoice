import { Badge } from "@/components/ui/badge";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { cn } from "@/lib/utils";

export type ModelRow = {
  id: string;
  name: string;
  promptPrice: number | null;
  completionPrice: number | null;
  toolRating: string;
  ragRating: string;
};

type Props = {
  models: ModelRow[];
  selectedId: string;
  onSelect: (id: string) => void;
};

const RATING_VARIANT: Record<string, "default" | "secondary" | "outline"> = {
  Best: "default",
  Strong: "secondary",
  Good: "outline",
};

function priceLabel(promptPrice: number | null, completionPrice: number | null) {
  const prompt = promptPrice?.toFixed(2) ?? "—";
  const completion = completionPrice?.toFixed(2) ?? "—";
  return `$${prompt} / $${completion} per 1M`;
}

export default function ModelComparison({ models, selectedId, onSelect }: Props) {
  return (
    <RadioGroup value={selectedId} onValueChange={onSelect} className="gap-3">
      {models.map((m) => {
        const selected = m.id === selectedId;
        return (
          <div
            key={m.id}
            role="button"
            tabIndex={0}
            onClick={() => onSelect(m.id)}
            onKeyDown={(e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                onSelect(m.id);
              }
            }}
            className={cn(
              "flex cursor-pointer items-center justify-between gap-4 rounded-lg border p-4 transition-colors hover:bg-accent/50",
              selected ? "border-primary ring-1 ring-primary" : "border-border",
            )}
          >
            <div className="flex items-center gap-3">
              <RadioGroupItem value={m.id} id={m.id} onClick={(e) => e.stopPropagation()} />
              <div>
                <p className="font-medium text-foreground">{m.name}</p>
                <p className="text-sm text-muted-foreground">
                  {priceLabel(m.promptPrice, m.completionPrice)}
                </p>
              </div>
            </div>
            <div className="flex shrink-0 items-center gap-2">
              <Badge variant={RATING_VARIANT[m.toolRating] ?? "outline"}>
                Tools: {m.toolRating}
              </Badge>
              <Badge variant={RATING_VARIANT[m.ragRating] ?? "outline"}>
                RAG: {m.ragRating}
              </Badge>
            </div>
          </div>
        );
      })}
    </RadioGroup>
  );
}
