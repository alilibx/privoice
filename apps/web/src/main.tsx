import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import { ConvexReactClient } from "convex/react";
import { ConvexAuthProvider } from "@convex-dev/auth/react";
import { ThemeProvider } from "@/lib/theme-provider";
import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import App from "./App";
// Self-hosted variable fonts (privacy: no Google Fonts CDN). Fraunces =
// display, Hanken Grotesk = UI/body, JetBrains Mono = tool args / model ids.
import "@fontsource-variable/fraunces";
import "@fontsource-variable/hanken-grotesk";
import "@fontsource-variable/jetbrains-mono";
import "./index.css";

const convex = new ConvexReactClient(import.meta.env.VITE_CONVEX_URL as string);

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ConvexAuthProvider client={convex}>
      <ThemeProvider>
        <TooltipProvider>
          <BrowserRouter>
            <App />
          </BrowserRouter>
          <Toaster />
        </TooltipProvider>
      </ThemeProvider>
    </ConvexAuthProvider>
  </React.StrictMode>,
);
