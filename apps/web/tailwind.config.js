/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  darkMode: "media",
  theme: {
    extend: {
      colors: {
        // calm-teal, mirrored from apps/mobile/lib/theme.dart
        primary: "#12708D",
        "primary-container": "#E0EFF4",
        "on-primary-container": "#0C5C76",
        surface: "#FFFFFF",
        "page-bg": "#EEF3F6",
        "on-surface": "#0F1D24",
        "on-surface-variant": "#5C6E77",
        outline: "#DDE7EC",
      },
      borderRadius: { xl: "18px", lg: "14px" },
    },
  },
  plugins: [],
};
