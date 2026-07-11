import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { useAuthActions } from "@convex-dev/auth/react";
import { api } from "../../convex/_generated/api";

export default function Dashboard() {
  const { signOut } = useAuthActions();
  const meetings = useQuery(api.meetings.list) ?? [];
  const create = useMutation(api.meetings.create);
  const remove = useMutation(api.meetings.remove);
  const [title, setTitle] = useState("");

  async function add(e: React.FormEvent) {
    e.preventDefault();
    const t = title.trim();
    if (!t) return;
    await create({ title: t, notes: undefined });
    setTitle("");
  }

  return (
    <main className="mx-auto max-w-2xl p-6">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-primary">Your meetings</h1>
        <button onClick={() => signOut()} className="text-sm text-primary">Sign out</button>
      </header>

      <form onSubmit={add} className="mt-6 flex gap-2">
        <input aria-label="New meeting title" value={title}
          onChange={(e) => setTitle(e.target.value)} placeholder="New meeting title"
          className="flex-1 rounded-lg border border-outline px-3 py-2" />
        <button type="submit"
          className="rounded-lg bg-primary px-4 py-2 font-semibold text-white">Add</button>
      </form>

      <ul className="mt-6 space-y-2">
        {meetings.map((m: any) => (
          <li key={m._id}
            className="flex items-center justify-between rounded-xl border border-outline bg-surface p-4">
            <span>{m.title}</span>
            <button onClick={() => remove({ id: m._id })}
              className="text-sm text-on-surface-variant hover:text-red-600">Delete</button>
          </li>
        ))}
        {meetings.length === 0 && (
          <li className="text-on-surface-variant">No meetings yet — add one above.</li>
        )}
      </ul>
    </main>
  );
}
