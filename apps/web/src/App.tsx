import { Authenticated, Unauthenticated, AuthLoading } from "convex/react";
import { Routes, Route, Navigate } from "react-router-dom";
import AppShell from "@/components/layout/AppShell";
import AuthForm from "@/features/auth/AuthForm";
import Chat from "@/features/chat/Chat";
import MeetingsList from "@/features/meetings/MeetingsList";
import DocumentsList from "@/features/documents/DocumentsList";
import SettingsPage from "@/features/settings/SettingsPage";

export default function App() {
  return (
    <>
      <AuthLoading><main className="grid min-h-screen place-items-center">Loading…</main></AuthLoading>
      <Unauthenticated><AuthForm /></Unauthenticated>
      <Authenticated>
        <Routes>
          <Route element={<AppShell />}>
            <Route path="/chat" element={<Chat />} />
            <Route path="/meetings" element={<MeetingsList />} />
            <Route path="/documents" element={<DocumentsList />} />
            <Route path="/settings" element={<SettingsPage />} />
            <Route path="*" element={<Navigate to="/chat" replace />} />
          </Route>
        </Routes>
      </Authenticated>
    </>
  );
}
