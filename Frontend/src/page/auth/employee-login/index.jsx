import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { employeeLogin } from "./service";
import useEmployeeSession  from "../../../sessions/employeeSession";
import useNonAdminSession from "../../../sessions/useNonAdminSession";
import useAdminSession    from "../../../sessions/adminSession";
import { syncLanguageFromSession } from "@/i18n/syncLanguage";
import empLogo from "@/assets/emp.png";
import smallempLogo from "@/assets/smallemp.png";
import userIcon from "@/assets/user-setting.png";
import ThemeToggle from "@/components/common/ThemeToggle";
import "../admin-login/style.css";

import { Input }  from "@/components/ui/input";
import { Label }  from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Eye, EyeOff, AlertCircle, Loader2 } from "lucide-react";

export const EmployeeLogin = () => {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { setEmployee } = useEmployeeSession();
  const { setNonAdmin } = useNonAdminSession();
  const { setAdmin }    = useAdminSession();

  const [email,        setEmail]        = useState("");
  const [password,     setPassword]     = useState("");
  const [loading,      setLoading]      = useState(false);
  const [error,        setError]        = useState("");
  const [showPassword, setShowPassword] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const result = await employeeLogin({ email, password });

      // Service returns { success, code, data } on success or { error } on failure.
      if (result.error) {
        setError(result.error);
        return;
      }
      if (!result?.success || result.code !== 200 || !result?.data) {
        setError(result.message || t("auth_login_failed"));
        return;
      }

      // Route by role string (mirrors Laravel logic)
      const apiResponse = result.data;
      syncLanguageFromSession();
      const role = (apiResponse.role || "").toLowerCase().replace(/\s+/g, "");
      if (role === "employee") {
        setEmployee(apiResponse);
        navigate("/employee/dashboard");
      } else if (apiResponse.is_admin) {
        setAdmin(apiResponse);
        navigate("/admin/dashboard");
      } else {
        setNonAdmin(apiResponse);
        navigate("/non-admin/dashboard");
      }
    } catch (err) {
      setError(t("auth_unexpected_error"));
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      className="relative min-h-screen flex flex-col overflow-hidden bg-[#F8FAFC] dark:bg-[#0B1120] text-slate-800 dark:text-slate-100 transition-colors duration-300 aca-hex-bg"
    >
      {/* Header */}
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

      {/* Main */}
      <main className="relative z-10 flex flex-1 items-center justify-end px-6 sm:px-16 lg:px-24 pb-12 max-w-[1700px] w-full">
        <div className="flex flex-col items-center justify-center max-w-[480px] w-full gap-4">
          <div
            className="animate-card-rise relative w-full rounded-3xl overflow-hidden px-8 sm:px-12 py-10 border border-slate-200/90 dark:border-slate-800/90 bg-white/95 dark:bg-[#131E32]/95 backdrop-blur-xl shadow-2xl shadow-sky-500/5 dark:shadow-black/60 transition-all duration-300"
          >
            {/* Top brand accent bar */}
            <div className="absolute top-0 left-0 right-0 h-1.5 shimmer-bar" />

            {/* Avatar */}
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
                {t("auth_employee_login")}
              </h2>
              <p className="text-[13px] text-slate-500 dark:text-slate-400 mt-1">
                {t("auth_sign_in_employee")}
              </p>
            </div>

            {/* Error banner */}
            {error && (
              <div className="animate-fade-in flex items-center gap-2 mb-5 px-3.5 py-2.5 rounded-xl text-[13px] text-red-700 bg-red-50 dark:bg-red-950/40 border border-red-200 dark:border-red-900 border-l-[3px] border-l-red-500">
                <AlertCircle size={16} className="shrink-0" />
                <span>{error}</span>
              </div>
            )}

            {/* Form */}
            <form onSubmit={handleSubmit} className="space-y-4">
              {/* Email */}
              <div className="space-y-1.5">
                <Label htmlFor="email" className="text-[13px] font-semibold text-slate-700 dark:text-slate-300">
                  {t("email")}
                </Label>
                <Input
                  id="email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                  placeholder={t("auth_enter_your_email")}
                  className={`emp-input px-4 h-11 rounded-xl text-sm text-slate-900 dark:text-slate-100 bg-white dark:bg-slate-900/80 placeholder:text-slate-400 border-[1.5px] transition-all duration-200 ${
                    error ? "border-red-300 emp-input-error" : "border-slate-200 dark:border-slate-700"
                  }`}
                />
              </div>

              {/* Password */}
              <div className="space-y-1.5">
                <Label htmlFor="password" className="text-[13px] font-semibold text-slate-700 dark:text-slate-300">
                  {t("password")}
                </Label>
                <div className="relative">
                  <Input
                    id="password"
                    type={showPassword ? "text" : "password"}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    placeholder={t("auth_enter_your_password")}
                    className={`emp-input px-4 pr-11 h-11 rounded-xl text-sm text-slate-900 dark:text-slate-100 bg-white dark:bg-slate-900/80 placeholder:text-slate-400 border-[1.5px] transition-all duration-200 ${
                      error ? "border-red-300 emp-input-error" : "border-slate-200 dark:border-slate-700"
                    }`}
                  />
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    tabIndex={-1}
                    onClick={() => setShowPassword((v) => !v)}
                    className="absolute right-1 top-1/2 -translate-y-1/2 h-8 w-8 text-slate-400 hover:text-[#30A9E3] hover:bg-transparent transition-colors duration-200"
                  >
                    {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                  </Button>
                </div>
              </div>

              {/* Submit */}
              <div className="pt-1">
                <Button
                  type="submit"
                  disabled={loading}
                  className="login-btn w-full h-11 rounded-xl text-[15px] font-bold text-white border-none transition-all duration-300 disabled:opacity-75 disabled:cursor-not-allowed bg-gradient-to-r from-[#30A9E3] to-[#0F7CB9] hover:from-[#2597ce] hover:to-[#0c6699] shadow-lg shadow-[#30A9E3]/20"
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

              <div className="flex justify-center !mt-2">
                <Button
                  type="button"
                  variant="ghost"
                  className="h-auto p-0 text-[13px] font-semibold text-[#30A9E3] hover:text-[#0F7CB9] dark:text-[#38BDF8] hover:bg-transparent hover:underline transition-opacity duration-200"
                >
                  {t("auth_forgot_password")}
                </Button>
              </div>
            </form>

            {/* Footer links */}
            <p className="text-center text-[13px] text-slate-500 dark:text-slate-400 leading-relaxed mt-5">
              {t("auth_admin_question")}{" "}
              <Button
                type="button"
                variant="ghost"
                className="h-auto p-0 text-[13px] font-bold text-[#30A9E3] hover:text-[#0F7CB9] dark:text-[#38BDF8] hover:bg-transparent hover:underline"
                onClick={() => navigate("/admin-login")}
              >
                {t("auth_admin_login")}
              </Button>
            </p>
          </div>

          <span className="text-xs text-slate-500 dark:text-slate-400">
            © {new Date().getFullYear()} ACA ADVISOR S.A.S. - Todos los derechos reservados
          </span>
        </div>
      </main>
    </div>
  );
};
