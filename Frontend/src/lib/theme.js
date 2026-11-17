import { create } from "zustand";

const THEME_KEY = "aca_theme";

const getInitialTheme = () => {
  if (typeof window === "undefined") return "light";
  try {
    const saved = localStorage.getItem(THEME_KEY);
    if (saved === "dark" || saved === "light") return saved;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  } catch {
    return "light";
  }
};

const applyThemeClass = (theme) => {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  if (theme === "dark") {
    root.classList.add("dark");
  } else {
    root.classList.remove("dark");
  }
};

export const useTheme = create((set, get) => {
  const initialTheme = getInitialTheme();
  applyThemeClass(initialTheme);

  return {
    theme: initialTheme,
    isDark: initialTheme === "dark",
    setTheme: (newTheme) => {
      const theme = newTheme === "dark" ? "dark" : "light";
      try {
        localStorage.setItem(THEME_KEY, theme);
      } catch (_) {}
      applyThemeClass(theme);
      set({ theme, isDark: theme === "dark" });
    },
    toggleTheme: () => {
      const current = get().theme;
      const nextTheme = current === "dark" ? "light" : "dark";
      get().setTheme(nextTheme);
    },
  };
});

export default useTheme;
