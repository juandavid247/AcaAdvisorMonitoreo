import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { NonAdminLogin, forgotPassword } from "./service";
import useNonAdminSession from "@/sessions/useNonAdminSession";
import useEmployeeSession from "@/sessions/employeeSession";
import useAdminSession    from "@/sessions/adminSession";
import { syncLanguageFromSession } from "@/i18n/syncLanguage";
import userBgIllustration from "@/assets/user-bg.png";
import "./style.css";
import "../admin-login/style.css";
import empLogo from "@/assets/emp.png";
import smallempLogo from "@/assets/smallemp.png";
import userIcon from "@/assets/user-setting.png";
// ── shadcn/ui components ──────────────────────────────────────────────────
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";

import { Eye, EyeOff, AlertCircle, Loader2, X } from "lucide-react";
import ThemeToggle from "@/components/common/ThemeToggle";
import {
  Dialog,
  DialogContent,
  DialogClose,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { Checkbox } from "@/components/ui/checkbox";

/* ========================================================================
   NonAdmin Login Component
   ======================================================================== */
export const Login = () => {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const { setNonAdmin } = useNonAdminSession();
  const { setEmployee } = useEmployeeSession();
  const { setAdmin }    = useAdminSession();

  const [showPassword, setShowPassword] = useState(false);
  const [focusedField, setFocusedField] = useState(null);
  const [rememberMe, setRememberMe] = useState(false);
  const [forgotOpen, setForgotOpen] = useState(false);
  const [forgotEmail, setForgotEmail] = useState("");
  const [forgotLoading, setForgotLoading] = useState(false);
  const [forgotMsg, setForgotMsg] = useState({ type: "", text: "" });

  const handleForgotSubmit = async () => {
    if (!forgotEmail.trim()) return;
    setForgotLoading(true);
    setForgotMsg({ type: "", text: "" });
    const res = await forgotPassword(forgotEmail.trim());
    setForgotLoading(false);
    if (res?.code === 200) {
      setForgotMsg({ type: "success", text: res.msg || t("auth_reset_link_sent") });
      setForgotEmail("");
    } else {
      setForgotMsg({ type: "error", text: res?.msg || res?.message || t("auth_reset_link_failed") });
    }
  };

  // ── Original handleSubmit — untouched ──────────────────────────────────
  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const result = await NonAdminLogin({ email, password });

      if (result.error) {
        setError(result.error);
        return;
      }

      if (!result?.data || result.code !== 200) {
        setError(result.message || t("auth_login_failed"));
        return;
      }

      // Route based on role flags in the API response.
      // Employees → employee session + employee dashboard.
      // Managers / teamleads → non-admin session (dashboard TBD).
      // Mirror Laravel logic: route by role string, not boolean flags
      const role = (result.role || "").toLowerCase().replace(/\s+/g, "");
      syncLanguageFromSession();
      if (role === "employee") {
        setEmployee(result);
        navigate("/employee/dashboard");
      } else if (result.is_admin) {
        setAdmin(result);
        navigate("/admin/dashboard");
      } else {
        setNonAdmin(result);
        navigate("/non-admin/dashboard");
      }
    } catch (err) {
      setError(t("auth_unexpected_error"));
      // eslint-disable-next-line no-console
      console.error(err);
    } finally {
      setLoading(false);
    }
  };
  // ───────────────────────────────────────────────────────────────────────

  return (
    <div
      className="relative min-h-screen flex flex-col overflow-hidden bg-[#F8FAFC] dark:bg-[#090F1D] text-slate-800 dark:text-slate-100 transition-colors duration-300 aca-hex-bg"
    >
      {/* ── Top-right Theme Toggle ────────────────────────────────────── */}
      <header className="animate-fade-down relative z-10 flex items-center justify-end px-6 sm:px-10 pt-5">
        <ThemeToggle />
      </header>

      {/* ── Centered Main Login Container ─────────────────────────────── */}
      <main className="relative z-10 flex flex-1 flex-col items-center justify-center px-4 sm:px-6 pb-10 pt-2 w-full">
        <div className="flex flex-col items-center justify-center max-w-[460px] w-full gap-5">
          {/* Large Centered Brand Logo */}
          <div className="animate-fade-down flex justify-center w-full">
            <img
              src={empLogo}
              alt="ACA ADVISOR S.A.S."
              className="h-32 sm:h-40 md:h-44 w-auto max-w-[360px] sm:max-w-[420px] object-contain drop-shadow-lg aca-logo-adaptive transition-all duration-200"
            />
          </div>

          <div
            className="animate-card-rise relative w-full rounded-3xl overflow-hidden px-7 sm:px-11 py-9 border border-slate-200/90 dark:border-slate-700/80 bg-white/95 dark:bg-[#111B2E]/95 backdrop-blur-xl shadow-2xl shadow-sky-500/10 dark:shadow-black/70 transition-all duration-300"
          >
            {/* Top brand accent bar */}
            <div className="absolute top-0 left-0 right-0 h-1.5 shimmer-bar" />

            {/* Title */}
            <div className="text-center mb-6 mt-1">
              <span className="text-xs font-bold uppercase tracking-widest text-[#30A9E3] dark:text-[#38BDF8]">
                ACA ADVISOR S.A.S.
              </span>
              <h2 className="text-xl sm:text-2xl font-bold tracking-tight text-[#0F7CB9] dark:text-white mt-1">
                {t("auth_login_to_account")}
              </h2>
            </div>

            {/* ── Error banner — same condition as original ── */}
            {error && (
              <div className="animate-fade-in flex items-center gap-2 mb-5 px-3.5 py-2.5 rounded-xl text-[13px] text-red-700 dark:text-red-200 bg-red-50 dark:bg-red-950/60 border border-red-200 dark:border-red-800 border-l-[3px] border-l-red-500">
                <AlertCircle size={16} className="shrink-0" />
                <span>{error}</span>
              </div>
            )}

            {/* ── Form — onSubmit unchanged ── */}
            <form onSubmit={handleSubmit} className="space-y-4">
              {/* ── Email field ── */}
              <div className="space-y-1.5">
                <Label
                  htmlFor="email"
                  className="text-[13px] font-semibold text-slate-700 dark:text-slate-100"
                >
                  {t("auth_email_address")}
                </Label>

                <Input
                  id="email"
                  type="text"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  onFocus={() => setFocusedField("email")}
                  onBlur={() => setFocusedField(null)}
                  required
                  placeholder={t("auth_enter_email_address")}
                  className={`
                  emp-input px-4 h-11 rounded-xl text-sm text-slate-900 dark:text-white
                  bg-white dark:bg-slate-900/90 placeholder:text-slate-400 dark:placeholder:text-slate-400 border-[1.5px]
                  transition-all duration-200
                  ${error ? "border-red-400 emp-input-error" : "border-slate-200 dark:border-slate-600"}
                `}
                />
              </div>

              {/* ── Password field ── */}
              <div className="space-y-1.5">
                <Label
                  htmlFor="password"
                  className="text-[13px] font-semibold text-slate-700 dark:text-slate-100"
                >
                  {t("password")}
                </Label>

                <div className="relative">
                  <Input
                    id="password"
                    type={showPassword ? "text" : "password"}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    onFocus={() => setFocusedField("password")}
                    onBlur={() => setFocusedField(null)}
                    required
                    placeholder={t("auth_enter_password")}
                    className={`
                    emp-input px-4 pr-11 h-11 rounded-xl text-sm text-slate-900 dark:text-white
                    bg-white dark:bg-slate-900/90 placeholder:text-slate-400 dark:placeholder:text-slate-400 border-[1.5px]
                    transition-all duration-200
                    ${error ? "border-red-400 emp-input-error" : "border-slate-200 dark:border-slate-600"}
                  `}
                  />

                  {/* Eye toggle */}
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    tabIndex={-1}
                    aria-label={
                      showPassword ? t("auth_hide_password") : t("auth_show_password")
                    }
                    onClick={() => setShowPassword((v) => !v)}
                    className="absolute right-1 top-1/2 -translate-y-1/2 h-8 w-8
                    text-slate-500 dark:text-slate-300 hover:text-[#30A9E3] dark:hover:text-[#38BDF8] hover:bg-transparent
                    transition-colors duration-200"
                  >
                    {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                  </Button>
                </div>
              </div>

              {/* ── Remember me + Forgot password ── */}
              <div className="flex items-center justify-between">
                <Label htmlFor="rememberMe" className="flex items-center gap-2 cursor-pointer select-none">
                  <Checkbox
                    id="rememberMe"
                    checked={rememberMe}
                    onChange={(e) => setRememberMe(e.target.checked)}
                    className="w-4 h-4 rounded border-slate-300 dark:border-slate-600 accent-[#30A9E3] cursor-pointer"
                  />
                  <span className="text-[13px] font-semibold text-slate-700 dark:text-slate-200">{t("auth_remember_password")}</span>
                </Label>
                <Button
                  type="button"
                  variant="ghost"
                  className="h-auto p-0 text-[13px] font-semibold text-[#0F7CB9] dark:text-[#7DD3FC]
                  hover:text-[#30A9E3] hover:bg-transparent hover:underline
                  transition-opacity duration-200"
                  onClick={() => { setForgotEmail(""); setForgotMsg({ type: "", text: "" }); setForgotOpen(true); }}
                >
                  {t("auth_forgot_password")}
                </Button>
              </div>

              {/* ── Submit — shadcn Button ── */}
              <div className="pt-1">
                <Button
                  type="submit"
                  disabled={loading}
                  className="login-btn w-full h-11 rounded-xl text-[15px] font-bold text-white border-none transition-all duration-300 disabled:opacity-75 disabled:cursor-not-allowed bg-gradient-to-r from-[#30A9E3] to-[#0F7CB9] hover:from-[#2998cd] hover:to-[#0d699c] shadow-md shadow-[#30A9E3]/25"
                >
                  {loading ? (
                    <span className="flex items-center gap-2">
                      <Loader2 size={17} className="animate-spin" />
                      {t("auth_logging_in")}
                    </span>
                  ) : (
                    t("auth_log_in")
                  )}
                </Button>
              </div>
            </form>

            {/* ── Admin Login — centered ── */}
            <div className="flex justify-center mt-4">
              <Button
                type="button"
                variant="ghost"
                className="h-auto p-0 text-[13px] font-bold text-[#0F7CB9] dark:text-[#7DD3FC]
                hover:text-[#30A9E3] hover:bg-transparent hover:underline"
                onClick={() => navigate("/admin-login")}
              >
                {t("auth_admin_login_question")}
              </Button>
            </div>
          </div>
          <span className="text-xs text-slate-600 dark:text-slate-300 text-center">© {new Date().getFullYear()} – ACA ADVISOR S.A.S. Todos los derechos reservados.</span>
        </div>
      </main>

      {/* ── Forgot Password Modal ── */}
      <Dialog open={forgotOpen} onOpenChange={setForgotOpen}>
        <DialogContent className="max-w-[95vw] sm:max-w-[500px] rounded-2xl p-0 border border-slate-200 dark:border-slate-700 shadow-2xl overflow-hidden gap-0 [&>button:last-child]:hidden bg-white dark:bg-[#111B2E] text-slate-900 dark:text-slate-100">
          <DialogTitle className="sr-only">{t("auth_forgot_password_title")}</DialogTitle>
          <DialogDescription className="sr-only">Enter your email to reset your password</DialogDescription>
          <div
            className="px-6 py-4 flex items-center justify-between"
            style={{ background: "linear-gradient(135deg, #0F7CB9 0%, #30A9E3 100%)" }}
          >
            <h2 className="text-white text-lg font-bold">{t("auth_forgot_password_title")}</h2>
            <DialogClose className="text-white hover:text-white/80 transition-colors focus:outline-none">
              <X className="h-5 w-5" />
            </DialogClose>
          </div>

          <div className="px-6 pt-6 pb-4 space-y-4">
            <Label className="text-[15px] font-semibold text-slate-800 dark:text-slate-100">
              {t("auth_email_address")}
            </Label>
            <Input
              type="email"
              placeholder={t("auth_enter_email")}
              value={forgotEmail}
              onChange={(e) => setForgotEmail(e.target.value)}
              className="h-12 rounded-xl border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-900 text-slate-900 dark:text-white text-sm px-4 placeholder:text-slate-400"
            />
            <p className="text-[13px] text-slate-600 dark:text-slate-300">
              {t("auth_email_privacy")}
            </p>
            {forgotMsg.text && (
              <p className={`text-[13px] font-medium ${forgotMsg.type === "success" ? "text-emerald-600 dark:text-emerald-400" : "text-red-500 dark:text-red-400"}`}>
                {forgotMsg.text}
              </p>
            )}
          </div>

          <div className="px-6 py-4 flex items-center justify-end gap-3">
            <DialogClose asChild>
              <Button className="h-10 px-6 rounded-full bg-slate-200 hover:bg-slate-300 dark:bg-slate-700 dark:hover:bg-slate-600 text-slate-800 dark:text-slate-100 text-[14px] font-semibold shadow-none">
                {t("close")}
              </Button>
            </DialogClose>
            <Button
              onClick={handleForgotSubmit}
              disabled={!forgotEmail.trim() || forgotLoading}
              className="h-10 px-6 rounded-full bg-[#0F7CB9] hover:bg-[#0d699c] text-white text-[14px] font-semibold disabled:opacity-50"
            >
              {forgotLoading ? <><Loader2 className="w-4 h-4 mr-1 animate-spin" /> {t("auth_sending")}</> : t("submit")}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};
