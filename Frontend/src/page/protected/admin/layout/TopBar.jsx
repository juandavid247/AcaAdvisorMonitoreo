import {
  HelpCircle,
  Settings,
  ShieldCheck,
  Fingerprint,
  LogOut,
} from "lucide-react";
import NotificationBell from "@/components/common/NotificationBell";
import { useTranslation } from "react-i18next";
import { SidebarTrigger, useSidebar } from "@/components/ui/sidebar";
import userData from "@/data/user.json";
import useAdminSession from "@/sessions/adminSession";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Avatar, AvatarImage, AvatarFallback } from "@/components/ui/avatar";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import UniPass from "@/components/common/UniPass";
import BackToCloud from "@/components/BackToCloud";
import aiWhiteLogo from "@/assets/ai_white_logo.svg";
import EmpAiAssistant from "@/components/common/aempaiassistant";
import { isEmpAiAssistantEnabled } from "@/lib/utils";
import ThemeToggle from "@/components/common/ThemeToggle";
import "./TopBar.css";

export default function TopHeader() {
  const { t } = useTranslation();
  const { open } = useSidebar();
  const { admin, clearAdmin } = useAdminSession();
  const [openUniPass, setOpenUniPass] = useState(false);
  const [aiAssistantOpen, setAiAssistantOpen] = useState(false);
  const showEmpAiAssistant = isEmpAiAssistantEnabled();
  const navigate = useNavigate();

  const handleLogout = () => {
    try {
      clearAdmin();
    } catch (e) {
      // ignore, navigation will still proceed
    }
    navigate("/admin-login");
  };

  return (
    <div className="flex items-center justify-between border-b sticky top-0 z-50 border-slate-200/80 dark:border-slate-800 bg-white dark:bg-[#0D1526] px-5 py-3 w-full transition-colors duration-200 shadow-xs">
      {/* Left — Greeting */}
      <div className="flex items-center gap-2">
        {(!open || window.innerWidth <= 768) && (
          <div className="trigger_button mr-3 flex h-7 w-7 items-center justify-center rounded-md bg-slate-100 hover:bg-slate-200 dark:bg-slate-800 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-300">
            <SidebarTrigger />
          </div>
        )}
        <div className="md:flex flex-col hidden">
          <span className="text-xs text-[#0F7CB9] dark:text-[#38BDF8] font-bold tracking-wide">
            {t("topbar_hi")}{" "}
            {admin?.user_name &&
              admin?.user_name?.charAt(0)?.toUpperCase() +
                admin?.user_name?.slice(1)}
            ,
          </span>
          <h2 className="text-lg font-bold text-[#0F7CB9] dark:text-white">
            {t("topbar_welcome")}
          </h2>
        </div>
      </div>

      {/* Right — Actions */}
      <div className="flex items-center gap-3 sm:gap-4">

        {showEmpAiAssistant && (
          <div className="emp-ai-btn-wrap relative inline-flex">
            <div
              aria-hidden="true"
              className="emp-ai-btn-glow pointer-events-none absolute -inset-0.5 rounded-[10px]"
            />
            <button
              type="button"
              onClick={() => setAiAssistantOpen(true)}
              aria-label="Open AI Assistant"
              className="emp-ai-btn relative flex items-center gap-1.5 rounded-[9px] px-3 py-1.5 cursor-pointer text-white text-[10px] font-semibold"
            >
              <img src={aiWhiteLogo} alt="" className="h-3.75" />
              AI ASSISTANT
            </button>
          </div>
        )}

        <BackToCloud />

        {/* Theme Toggle Selector (Light / Dark) */}
        <ThemeToggle />

        {/* Help */}
        <a
          href="http://help.empmonitor.com/"
          target="_blank"
          rel="noreferrer"
          className="flex items-center gap-1 text-sm text-slate-600 hover:text-[#0F7CB9] dark:text-slate-200 dark:hover:text-white transition-colors"
        >
          <HelpCircle className="h-4 w-4" />
          {t("topbar_help")}
        </a>

        {/* Notification Bell */}
        <NotificationBell viewAllPath="/admin/behaviour/alertnotification" />

        {/* Profile Dropdown */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Avatar className="h-9 w-9 cursor-pointer ring-2 ring-[#30A9E3]/30 transition-all hover:ring-[#30A9E3]">
              <AvatarImage src={userData.avatar} alt={userData.firstName} />
              <AvatarFallback>{userData.firstName?.[0]}</AvatarFallback>
            </Avatar>
          </DropdownMenuTrigger>
          <DropdownMenuContent
            className="w-64 p-2 rounded-2xl shadow-2xl border border-slate-200 dark:border-slate-800 bg-white dark:bg-slate-900 text-slate-800 dark:text-slate-100 mt-2"
            align="end"
          >
            {/* User Info Section */}
            <div className="flex items-center gap-3 px-3 py-4">
              <Avatar className="h-10 w-10 ring-2 ring-[#30A9E3]/20">
                <AvatarImage src={userData.avatar} alt={userData.firstName} />
                <AvatarFallback>{userData.firstName?.[0]}</AvatarFallback>
              </Avatar>
              <div className="flex flex-col overflow-hidden">
                <span className="font-bold text-[#0F7CB9] dark:text-white truncate text-base">
                  {admin?.user_name
                    ? admin.user_name.charAt(0).toUpperCase() +
                      admin.user_name.slice(1)
                    : "Admin"}
                </span>
                <span className="text-xs text-slate-500 dark:text-slate-400 font-medium">
                  {t("topbar_admin")}
                </span>
              </div>
            </div>

            <DropdownMenuSeparator className="bg-slate-100 dark:bg-slate-800 border-dashed border-t h-px mx-0 my-2" />

            {/* Menu Items */}
            <div className="space-y-1">
              <DropdownMenuItem className="py-2.5 px-3 rounded-xl cursor-pointer hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors group">
                <div className="flex items-center gap-3 w-full">
                  <div className="p-1.5 rounded-lg bg-[#E0F2FE] dark:bg-slate-800 text-[#0F7CB9] dark:text-[#38BDF8] group-hover:bg-[#B6DDE2]/60 transition-colors">
                    <Settings className="h-4 w-4" />
                  </div>
                  <span className="text-sm font-semibold text-slate-700 dark:text-slate-200">
                    {t("topbar_account_settings")}
                  </span>
                </div>
              </DropdownMenuItem>

              <DropdownMenuItem className="py-2.5 px-3 rounded-xl cursor-pointer hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors group" onClick={() => setOpenUniPass(true)}>
                <div className="flex items-center gap-3 w-full">
                  <div className="p-1.5 rounded-lg bg-[#E0F2FE] dark:bg-slate-800 text-[#0F7CB9] dark:text-[#38BDF8] group-hover:bg-[#B6DDE2]/60 transition-colors">
                    <ShieldCheck className="h-4 w-4" />
                  </div>
                  <span className="text-sm font-semibold text-slate-700 dark:text-slate-200">
                    {t("topbar_uninstall_password")}
                  </span>
                </div>
              </DropdownMenuItem>
            </div>

            <DropdownMenuSeparator className="bg-slate-100 dark:bg-slate-800 mx-0 my-2" />

            {/* Logout Section */}
            <DropdownMenuItem
              className="py-2.5 px-3 rounded-xl cursor-pointer hover:bg-red-50 dark:hover:bg-red-950/40 transition-colors group mt-1 text-red-600 dark:text-red-400"
              onClick={handleLogout}
            >
              <div className="flex items-center gap-3 w-full">
                <div className="p-1.5 rounded-lg bg-red-50 dark:bg-red-950/60 text-[#EF4444] group-hover:bg-red-100 transition-colors">
                  <LogOut className="h-4 w-4" />
                </div>
                <span className="text-sm font-semibold">{t("topbar_logout")}</span>
              </div>
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

       <UniPass isOpen={openUniPass} onClose={() => setOpenUniPass(false)}/>

       {showEmpAiAssistant && (
         <EmpAiAssistant
           open={aiAssistantOpen}
           onClose={() => setAiAssistantOpen(false)}
         />
       )}
    </div>

  );
}
