import React from "react";
import { Sun, Moon } from "lucide-react";
import useTheme from "@/lib/theme";

export const ThemeToggle = ({ className = "" }) => {
  const { theme, toggleTheme } = useTheme();
  const isDark = theme === "dark";

  return (
    <button
      type="button"
      onClick={toggleTheme}
      aria-label={isDark ? "Cambiar a modo claro" : "Cambiar a modo oscuro"}
      title={isDark ? "Modo Claro" : "Modo Oscuro"}
      className={`relative inline-flex items-center justify-center p-2 rounded-xl transition-all duration-200 cursor-pointer
        ${isDark 
          ? "bg-slate-800/90 text-amber-300 hover:bg-slate-700 border border-slate-700/80 shadow-sm" 
          : "bg-slate-100/90 text-slate-700 hover:bg-slate-200 border border-slate-200/80 shadow-sm"}
        hover:scale-105 active:scale-95 focus:outline-none focus:ring-2 focus:ring-[#30A9E3]/50 ${className}`}
    >
      <div className="relative w-5 h-5 flex items-center justify-center">
        {isDark ? (
          <Sun className="w-4.5 h-4.5 transition-transform duration-300 rotate-0 scale-100" />
        ) : (
          <Moon className="w-4.5 h-4.5 transition-transform duration-300 rotate-0 scale-100 text-[#0F7CB9]" />
        )}
      </div>
    </button>
  );
};

export default ThemeToggle;
