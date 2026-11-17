import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { adminLogin, adminForgotPassword } from "./service";
import useAdminSession from "../../../sessions/adminSession";
import { syncLanguageFromSession } from "@/i18n/syncLanguage";
import bgIllustration from "@/assets/login-bg.png";
import "./style.css";
import empLogo from "@/assets/emp.png";
import smallempLogo from "@/assets/smallemp.png";
import userIcon from "@/assets/user-setting.png";
// ── shadcn/ui components ──────────────────────────────────────────────────
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import ThemeToggle from "@/components/common/ThemeToggle";

import {
  Dialog,
  DialogContent,
  DialogClose,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";

// ── Lucide React icons ────────────────────────────────────────────────────
import {
  Eye,
  EyeOff,
  AlertCircle,
  Loader2,
  UserRound,
  Settings,
  X,
} from "lucide-react";

/* ========================================================================
   AdminLogin Component
   ======================================================================== */
export const AdminLogin = () => {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const { setAdmin } = useAdminSession();

  const [showPassword, setShowPassword] = useState(false);
  const [focusedField, setFocusedField] = useState(null);
  const [forgotOpen, setForgotOpen] = useState(false);
  const [forgotEmail, setForgotEmail] = useState("");
  const [forgotLoading, setForgotLoading] = useState(false);
  const [forgotMsg, setForgotMsg] = useState({ type: "", text: "" });

  const handleForgotSubmit = async () => {
    if (!forgotEmail.trim()) return;
    setForgotLoading(true);
    setForgotMsg({ type: "", text: "" });
    const res = await adminForgotPassword(forgotEmail.trim());
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
      const result = await adminLogin({ email, password });

      // Handle service-level error (caught in service.js)
      if (result?.error && !result?.success) {
        setError(result.error);
        return;
      }

      // A successful login is identified by HTTP-level code 200 plus a token in
      // `data`. The `success` flag is only present on the v1/EmpCloud response
      // shape; the v3 proxy response omits it (and sets message:'token'), so we
      // must NOT require `success` here — otherwise a valid login is rejected
      // and the literal "token" message is shown in the error banner.
      const isSuccess = result?.code === 200 && !!result?.data;
      if (!isSuccess) {
        setError(result?.message || t("auth_login_failed"));
        return;
      }

      // Inner data-level error (only when `data` is an object, not the token string)
      if (result.data && typeof result.data === "object" && result.data.error) {
        setError(result.data.error);
        return;
      }

      setAdmin(result);
      syncLanguageFromSession();
      navigate("/admin/dashboard");
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
      className="relative min-h-screen flex flex-col overflow-hidden bg-[#F8FAFC] dark:bg-[#0B1120] text-slate-800 dark:text-slate-100 transition-colors duration-300 aca-hex-bg"
    >
      {/* ── Header ────────────────────────────────────────────────────── */}
      <header className="animate-fade-down relative z-10 flex items-center justify-between px-6 sm:px-12 py-5 sm:py-7">
        <div className="flex items-center gap-3">
          <img
            src={empLogo}
            alt="ACA ADVISOR S.A.S."
            className="h-24 sm:h-32 md:h-36 w-auto max-w-[280px] sm:max-w-[420px] object-contain drop-shadow-md transition-all duration-200"
          />
        </div>
        <div className="flex items-center gap-3">
          <ThemeToggle />
        </div>
      </header>

      {/* ── Main ──────────────────────────────────────────────────────── */}
      <main className="relative z-10 flex flex-1 items-center justify-end px-6 sm:px-16 lg:px-24 pb-12 max-w-[1700px] w-full">
        <div className="flex flex-col items-center justify-center max-w-[480px] w-full gap-4">
          <div
            className="animate-card-rise relative w-full rounded-3xl overflow-hidden px-8 sm:px-12 py-10 border border-slate-200/90 dark:border-slate-800/90 bg-white/95 dark:bg-[#131E32]/95 backdrop-blur-xl shadow-2xl shadow-sky-500/5 dark:shadow-black/60 transition-all duration-300"
          >
            {/* Top brand accent bar */}
            <div className="absolute top-0 left-0 right-0 h-1.5 shimmer-bar" />

            {/* ── Avatar / Brand Icon ── */}
            <div className="flex justify-center mb-5 mt-2">
              <div className="w-16 h-16 rounded-2xl bg-gradient-to-tr from-[#30A9E3]/15 to-[#3A9F6B]/15 dark:from-[#30A9E3]/25 dark:to-[#3A9F6B]/25 flex items-center justify-center border border-[#30A9E3]/25 shadow-md">
                <img src={smallempLogo} alt="ACA ADVISOR" className="w-10 h-10 object-contain drop-shadow-sm" />
              </div>
            </div>

            {/* Title */}
            <div className="text-center mb-7">
              <span className="text-[11px] font-bold uppercase tracking-wider text-[#30A9E3] dark:text-[#38BDF8]">
                ACA ADVISOR S.A.S.
              </span>
              <h2 className="text-xl sm:text-2xl font-bold tracking-tight text-[#0F7CB9] dark:text-white mt-1">
                {t("auth_login_to_account")}
              </h2>
            </div>

            {/* ── Error banner — same condition as original ── */}
            {error && (
              <div className="animate-fade-in flex items-center gap-2 mb-5 px-3.5 py-2.5 rounded-xl text-[13px] text-red-700 bg-red-50 border border-red-200 border-l-[3px] border-l-red-400">
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
                  className="text-[13px] font-semibold text-[#3a5a7a]"
                >
                  {t("auth_username")}
                </Label>

                <Input
                  id="email"
                  type="text"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  onFocus={() => setFocusedField("email")}
                  onBlur={() => setFocusedField(null)}
                  required
                  placeholder={t("auth_enter_username")}
                  className={`
                  emp-input px-4 h-11 rounded-xl text-sm text-[#1a2a4a]
                  bg-white/80 placeholder:text-[#aac4d8] border-[1.5px]
                  transition-all duration-200
                  ${error ? "border-red-300 emp-input-error" : "border-[#e0eef5]"}
                `}
                />
              </div>

              {/* ── Password field ── */}
              <div className="space-y-1.5">
                <Label
                  htmlFor="password"
                  className="text-[13px] font-semibold text-[#3a5a7a]"
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
                    emp-input px-4 pr-11 h-11 rounded-xl text-sm text-[#1a2a4a]
                    bg-white/80 placeholder:text-[#aac4d8] border-[1.5px]
                    transition-all duration-200
                    ${error ? "border-red-300 emp-input-error" : "border-[#e0eef5]"}
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
                    text-[#9bbdce] hover:text-[#2079FD] hover:bg-transparent
                    transition-colors duration-200"
                  >
                    {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                  </Button>
                </div>
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

              {/* ── Forgot password — below submit ── */}
              <div className="flex justify-center !mt-2">
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => { setForgotEmail(""); setForgotMsg({ type: "", text: "" }); setForgotOpen(true); }}
                  className="h-auto p-0 text-[13px] font-semibold text-[#0F7CB9] dark:text-[#38BDF8]
                  hover:text-[#30A9E3] hover:bg-transparent hover:underline
                  transition-opacity duration-200"
                >
                  {t("auth_forgot_password")}
                </Button>
              </div>
            </form>

            {/* Register row */}
            <p className="text-center text-[13px] text-slate-500 dark:text-slate-400 leading-relaxed mt-5">
              {t("auth_not_registered")}{" "}
              <Button
                type="button"
                variant="ghost"
                className="h-auto p-0 text-[13px] font-bold text-[#0F7CB9] dark:text-[#38BDF8]
                hover:text-[#30A9E3] hover:bg-transparent hover:underline"
              >
                {t("auth_sign_up")}
              </Button>
              <br /> {t("auth_manager_teamed_employee")}{" "}
              <Button
                type="button"
                variant="ghost"
                className="h-auto p-0 text-[13px] font-bold text-[#0F7CB9] dark:text-[#38BDF8]
                hover:text-[#30A9E3] hover:bg-transparent hover:underline"
                onClick={() => navigate("/login")}
              >
                {t("auth_login")}
              </Button>
            </p>
          </div>
          <span className="text-xs text-slate-500 dark:text-slate-400">© {new Date().getFullYear()} – ACA ADVISOR S.A.S. Todos los derechos reservados.</span>
        </div>
        {/* ── Login Card ──────────────────────────────────────────────── */}
      </main>

      {/* ── Forgot Password Modal ── */}
      <Dialog open={forgotOpen} onOpenChange={setForgotOpen}>
        <DialogContent className="max-w-[95vw] sm:max-w-[500px] rounded-2xl p-0 border border-slate-200 dark:border-slate-800 shadow-2xl overflow-hidden gap-0 [&>button:last-child]:hidden bg-white dark:bg-slate-900 text-slate-900 dark:text-slate-100">
          <DialogTitle className="sr-only">{t("auth_forgot_password_title")}</DialogTitle>
          <DialogDescription className="sr-only">Enter your email to reset your password</DialogDescription>
          {/* Header */}
          <div
            className="px-6 py-4 flex items-center justify-between"
            style={{ background: "linear-gradient(135deg, #0F7CB9 0%, #30A9E3 100%)" }}
          >
            <h2 className="text-white text-lg font-bold">{t("auth_forgot_password_title")}</h2>
            <DialogClose className="text-white hover:text-white/80 transition-colors focus:outline-none">
              <X className="h-5 w-5" />
            </DialogClose>
          </div>

          {/* Body */}
          <div className="px-6 pt-6 pb-4 space-y-4">
            <Label className="text-[15px] font-semibold text-gray-800">
              {t("auth_email_address")}
            </Label>
            <Input
              type="email"
              placeholder={t("auth_enter_email")}
              value={forgotEmail}
              onChange={(e) => setForgotEmail(e.target.value)}
              className="h-12 rounded-xl border-gray-300 text-sm px-4 placeholder:text-gray-400"
            />
            <p className="text-[13px] text-gray-500">
              {t("auth_email_privacy")}
            </p>
            {forgotMsg.text && (
              <p className={`text-[13px] font-medium ${forgotMsg.type === "success" ? "text-green-600" : "text-red-500"}`}>
                {forgotMsg.text}
              </p>
            )}
          </div>

          {/* Footer */}
          <div className="px-6 py-4 flex items-center justify-end gap-3">
            <DialogClose asChild>
              <Button className="h-10 px-6 rounded-full bg-gray-300 hover:bg-gray-400 text-gray-700 text-[14px] font-semibold shadow-none">
                {t("close")}
              </Button>
            </DialogClose>
            <Button
              onClick={handleForgotSubmit}
              disabled={!forgotEmail.trim() || forgotLoading}
              className="h-10 px-6 rounded-full bg-blue-500 hover:bg-blue-600 text-white text-[14px] font-semibold disabled:opacity-50"
            >
              {forgotLoading ? <><Loader2 className="w-4 h-4 mr-1 animate-spin" /> {t("auth_sending")}</> : t("submit")}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};
