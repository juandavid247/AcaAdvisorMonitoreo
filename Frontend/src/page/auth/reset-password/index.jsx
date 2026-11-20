import React, { useMemo, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { resetPassword } from "./service";
import empLogo from "@/assets/emp.png";
import smallempLogo from "@/assets/smallemp.png";
import userIcon from "@/assets/user-setting.png";
import ThemeToggle from "@/components/common/ThemeToggle";
import "../admin-login/style.css";

import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Eye, EyeOff, AlertCircle, CheckCircle2, Loader2 } from "lucide-react";

export const ResetPassword = () => {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const [params] = useSearchParams();

  const token = (params.get("token") || "").trim();
  const email = (params.get("email") || "").trim();
  const isClient = params.get("isClient");

  const tokenValid = useMemo(() => token.length > 0 && email.length > 0, [token, email]);

  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showNew, setShowNew] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setSuccess("");

    if (!tokenValid) {
      setError(t("auth_reset_invalid_link") || "Invalid or expired reset link.");
      return;
    }
    if (newPassword.length < 6) {
      setError(t("auth_reset_password_too_short") || "Password must be at least 6 characters.");
      return;
    }
    if (newPassword !== confirmPassword) {
      setError(t("auth_reset_password_mismatch") || "Passwords do not match.");
      return;
    }

    setLoading(true);
    const res = await resetPassword({
      email,
      token,
      new_password: newPassword,
      confirm_password: confirmPassword,
      isClient,
    });
    setLoading(false);

    if (res?.code === 200) {
      setSuccess(res.message || t("auth_reset_password_success") || "Password updated. Redirecting to login…");
      setTimeout(() => navigate("/login", { replace: true }), 1800);
    } else {
      setError(res?.message || t("auth_reset_password_failed") || "Unable to update password.");
    }
  };

  return (
    <div
      className="relative min-h-screen flex flex-col overflow-hidden bg-[#F8FAFC] dark:bg-[#090F1D] text-slate-800 dark:text-slate-100 transition-colors duration-300 aca-hex-bg"
    >
      {/* Subtle ambient glow for dark & light depth */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -top-32 left-1/2 -translate-x-1/2 h-96 w-[620px] rounded-full bg-[#30A9E3]/10 dark:bg-[#38BDF8]/12 blur-3xl"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -bottom-40 right-1/4 h-80 w-[480px] rounded-full bg-[#3A9F6B]/10 dark:bg-[#4ADE80]/8 blur-3xl"
      />

      {/* Top-right Theme Toggle */}
      <header className="animate-fade-down relative z-10 flex items-center justify-end px-6 sm:px-10 pt-5">
        <ThemeToggle />
      </header>

      {/* Centered Main */}
      <main className="relative z-10 flex flex-1 flex-col items-center justify-center px-4 sm:px-6 pb-10 pt-2 w-full">
        <div className="flex flex-col items-center justify-center max-w-[440px] w-full gap-4">
          <div
            className="animate-card-rise relative w-full rounded-3xl overflow-hidden px-7 sm:px-10 pt-9 pb-8 border border-slate-200/90 dark:border-slate-700/70 bg-white/95 dark:bg-[#111B2E]/95 backdrop-blur-xl shadow-2xl shadow-sky-500/10 dark:shadow-[0_24px_60px_-15px_rgba(0,0,0,0.75)] transition-all duration-300"
          >
            {/* Top brand accent bar */}
            <div className="absolute top-0 left-0 right-0 h-1.5 shimmer-bar" />

            <div className="flex flex-col items-center text-center mb-6">
              <div className="mb-4 flex justify-center w-full">
                <img
                  src={empLogo}
                  alt="ACA ADVISOR S.A.S."
                  className="h-24 sm:h-28 w-auto max-w-[260px] object-contain aca-logo-adaptive transition-all duration-200"
                />
              </div>
              <h2 className="text-lg sm:text-xl font-bold tracking-tight text-[#0F7CB9] dark:text-slate-100">
                {t("auth_reset_password_title") || "Reset your password"}
              </h2>
              {email && (
                <p className="mt-1 text-[13px] text-slate-500 dark:text-slate-400 break-all">{email}</p>
              )}
            </div>

            {!tokenValid && (
              <div className="animate-fade-in flex items-center gap-2 mb-5 px-3.5 py-2.5 rounded-xl text-[13px] text-red-700 dark:text-red-200 bg-red-50 dark:bg-red-950/60 border border-red-200 dark:border-red-800 border-l-[3px] border-l-red-500">
                <AlertCircle size={16} className="shrink-0" />
                <span>{t("auth_reset_invalid_link") || "Invalid or expired reset link."}</span>
              </div>
            )}

            {error && (
              <div className="animate-fade-in flex items-center gap-2 mb-5 px-3.5 py-2.5 rounded-xl text-[13px] text-red-700 dark:text-red-200 bg-red-50 dark:bg-red-950/60 border border-red-200 dark:border-red-800 border-l-[3px] border-l-red-500">
                <AlertCircle size={16} className="shrink-0" />
                <span>{error}</span>
              </div>
            )}

            {success && (
              <div className="animate-fade-in flex items-center gap-2 mb-5 px-3.5 py-2.5 rounded-xl text-[13px] text-emerald-700 dark:text-emerald-200 bg-emerald-50 dark:bg-emerald-950/60 border border-emerald-200 dark:border-emerald-800 border-l-[3px] border-l-emerald-500">
                <CheckCircle2 size={16} className="shrink-0" />
                <span>{success}</span>
              </div>
            )}

            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="space-y-1.5">
                <Label htmlFor="new_password" className="text-[13px] font-semibold text-slate-700 dark:text-slate-100">
                  {t("auth_new_password") || "New password"}
                </Label>
                <div className="relative">
                  <Input
                    id="new_password"
                    type={showNew ? "text" : "password"}
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    required
                    disabled={!tokenValid || loading || !!success}
                    placeholder={t("auth_enter_new_password") || "Enter new password"}
                    className="emp-input px-4 pr-11 h-11 rounded-xl text-sm text-slate-900 dark:text-white bg-white dark:bg-slate-900/90 placeholder:text-slate-400 border-[1.5px] border-slate-200 dark:border-slate-600 transition-all duration-200"
                  />
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    tabIndex={-1}
                    onClick={() => setShowNew((v) => !v)}
                    className="absolute right-1 top-1/2 -translate-y-1/2 h-8 w-8 text-slate-500 dark:text-slate-300 hover:text-[#30A9E3] dark:hover:text-[#38BDF8] hover:bg-transparent transition-colors duration-200"
                  >
                    {showNew ? <EyeOff size={16} /> : <Eye size={16} />}
                  </Button>
                </div>
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="confirm_password" className="text-[13px] font-semibold text-slate-700 dark:text-slate-100">
                  {t("auth_confirm_password") || "Confirm password"}
                </Label>
                <div className="relative">
                  <Input
                    id="confirm_password"
                    type={showConfirm ? "text" : "password"}
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    required
                    disabled={!tokenValid || loading || !!success}
                    placeholder={t("auth_reenter_new_password") || "Re-enter new password"}
                    className="emp-input px-4 pr-11 h-11 rounded-xl text-sm text-slate-900 dark:text-white bg-white dark:bg-slate-900/90 placeholder:text-slate-400 border-[1.5px] border-slate-200 dark:border-slate-600 transition-all duration-200"
                  />
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    tabIndex={-1}
                    onClick={() => setShowConfirm((v) => !v)}
                    className="absolute right-1 top-1/2 -translate-y-1/2 h-8 w-8 text-slate-500 dark:text-slate-300 hover:text-[#30A9E3] dark:hover:text-[#38BDF8] hover:bg-transparent transition-colors duration-200"
                  >
                    {showConfirm ? <EyeOff size={16} /> : <Eye size={16} />}
                  </Button>
                </div>
              </div>

              <div className="pt-1">
                <Button
                  type="submit"
                  disabled={loading || !tokenValid || !!success}
                  className="login-btn w-full h-11 rounded-xl text-[15px] font-bold text-white border-none transition-all duration-300 disabled:opacity-75 disabled:cursor-not-allowed bg-gradient-to-r from-[#30A9E3] to-[#0F7CB9] hover:from-[#2597ce] hover:to-[#0c6699] shadow-lg shadow-[#30A9E3]/20"
                >
                  {loading ? (
                    <span className="flex items-center gap-2">
                      <Loader2 size={17} className="animate-spin" />
                      {t("auth_updating") || "Updating…"}
                    </span>
                  ) : (
                    t("auth_update_password") || "Update password"
                  )}
                </Button>
              </div>
            </form>

            <div className="flex justify-center mt-4">
              <Button
                type="button"
                variant="ghost"
                className="h-auto p-0 text-[13px] font-bold text-[#0F7CB9] hover:text-[#30A9E3] dark:text-[#7DD3FC] hover:bg-transparent hover:underline"
                onClick={() => navigate("/login")}
              >
                {t("auth_back_to_login") || "Back to login"}
              </Button>
            </div>
          </div>
          <span className="text-xs text-slate-600 dark:text-slate-300 text-center">© {new Date().getFullYear()} ACA ADVISOR S.A.S. - Todos los derechos reservados</span>
        </div>
      </main>
    </div>
  );
};

export default ResetPassword;
