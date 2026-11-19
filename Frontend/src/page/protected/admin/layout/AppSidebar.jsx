import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import empLogo from "@/assets/emp.png";
import smallempLogo from "@/assets/smallemp.png";
import favLogo from "@/assets/fav.png";
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarMenu,
  SidebarFooter,
  SidebarHeader,
  useSidebar,
  SidebarTrigger,
} from "@/components/ui/sidebar";
import {
  LayoutDashboard,
  Users,
  Clock,
  History,
  Monitor,
  HandCoins,
  Briefcase,
  BarChart3,
  ShieldAlert,
  Settings2,
  Zap,
  Download,
  Smartphone,
  Code2,
  ReceiptText,
  Key,
  Store,
  ToggleRight,
} from "lucide-react";
import AppMenuItems from "./AppMenuItems";
import { ShimmerButton } from "@/components/ui/shimmer-button";
import downloadIcon from "@/assets/agentdwnld.png";
import AgentDownloadOverlay from "@/page/protected/admin/agent-download";
import apiService from "@/services/api.service";
import useAdminSession from "@/sessions/adminSession";
import { getSessionCookie } from "@/lib/sessionCookie";

// Mirrors the backend gate: super admin OR a user in the env-configured
// operator org can see and use the addon-features console.
const hasAddonFeaturesAccess = (session) => {
  if (!session) return false;
  if (session.is_admin === true) return true;
  const raw = import.meta.env.VITE_ADDON_SUPERADMIN_ORG_ID;
  if (raw === undefined || raw === null || raw === "") return false;
  const operatorOrgId = Number(raw);
  if (!Number.isFinite(operatorOrgId)) return false;
  return Number(session.organization_id) === operatorOrgId;
};

const getMenuItems = (t, { showAddonFeatures = false } = {}) => [
  { title: t("dashboard"), url: "/admin/dashboard", icon: LayoutDashboard },
  {
    title: t("employees"),
    icon: Users,
    children: [
      { title: t("sidebar_employees_details"), url: "/admin/employee-details" },
      { title: t("sidebar_employee_comparison"), url: "/admin/comparison" },
      { title: t("sidebar_employee_attendance"), url: "/admin/attendance" },
      { title: t("sidebar_employee_insights"), url: "/admin/insights" },
      { title: t("sidebar_real_time_track"), url: "/admin/realtime" },
    ],
  },
  { title: t("timesheets"), url: "/admin/timesheets", icon: Clock },
  { title: t("sidebar_live_monitoring"), url: "/admin/livemonitoring", icon: Monitor },
  { title: t("sidebar_time_claim"), url: "/admin/timeclaim", icon: HandCoins },
  {
    title: t("reports"),
    icon: BarChart3,
    children: [
      { title: t("sidebar_reports_download"), url: "/admin/reports/download" },
      { title: t("sidebar_productivity_report"), url: "/admin/reports/productivity" },
      { title: t("sidebar_auto_email_report"), url: "/admin/reports/autoemail" },
      { title: t("sidebar_web_app_usage"), url: "/admin/reports/webappusage" },
    ],
  },
  {
    title: t("sidebar_dlp"),
    icon: ShieldAlert,
    children: [
      { title: t("sidebar_usb_detection"), url: "/admin/dlp/usb" },
      { title: t("sidebar_system_logs"), url: "/admin/dlp/systemlogs" },
      // { title: t("sidebar_screenshot_logs"), url: "/admin/dlp/screenshotlogs" },
      { title: t("sidebar_email_activity_logs"), url: "/admin/dlp/emailactivitylogs" },
    ],
  },
  {
    title: t("settings"),
    icon: Settings2,
    children: [
      { title: t("sidebar_manage_location_dept"), url: "/admin/settings/location" },
      { title: t("sidebar_storage_types"), url: "/admin/settings/storage" },
      { title: t("sidebar_productivity_rules"), url: "/admin/settings/productivity" },
      { title: t("sidebar_roles_permissions"), url: "/admin/settings/roles" },
      { title: t("sidebar_shift_management"), url: "/admin/settings/shift" },
      { title: t("sidebar_monitoring_control"), url: "/admin/settings/monitoring" },
      { title: t("localization"), url: "/admin/settings/localization" },
    ],
  },
  {
    title: t("behaviour"),
    icon: Zap,
    children: [
      { title: t("alerts"), url: "/admin/behaviour/alerts" },
      { title: t("sidebar_alert_policies"), url: "/admin/behaviour/alertpolicies" },
      { title: t("sidebar_alert_notification"), url: "/admin/behaviour/alertnotification" },
    ],
  },
];

const normalizeResellerStats = (payload = {}) => {
  const rawExpiry = String(payload.expiry_date || "").replace(/"/g, "").trim();
  const formattedExpiry = rawExpiry
    ? new Date(rawExpiry).toLocaleDateString("en-GB")
    : "-";

  return {
    totalLicenses: Number(payload.total_licenses_count) || 0,
    usedLicenses: Number(payload.total_licenses_used_by_me) || 0,
    leftLicenses: Number(payload.left_over_licenses) || 0,
    expiryDate: formattedExpiry === "Invalid Date" ? rawExpiry || "-" : formattedExpiry,
  };
};

export function AppSidebar() {
  const { t } = useTranslation();
  const { open } = useSidebar();
  const [openKey, setOpenKey] = useState(null);
  const [agentDownloadOpen, setAgentDownloadOpen] = useState(false);
  const { admin } = useAdminSession();
  // Cookie fallback for the first paint before the store hydrates.
  const session = admin || getSessionCookie();
  const showAddonFeatures = hasAddonFeaturesAccess(session);
  const menuItems = getMenuItems(t, { showAddonFeatures });
  const [licenseStats, setLicenseStats] = useState({
    totalLicenses: 0,
    usedLicenses: 0,
    leftLicenses: 0,
    expiryDate: "-",
  });

  useEffect(() => {
    const controller = new AbortController();

    const loadResellerStats = async () => {
      try {
        const { data } = await apiService.apiInstance.get("/settings/reseller-stats", {
          signal: controller.signal,
        });
        if (data?.code !== 200 || !data?.data) return;

        const nextStats = normalizeResellerStats(data.data);
        setLicenseStats((prev) => (
          prev.totalLicenses === nextStats.totalLicenses &&
          prev.usedLicenses === nextStats.usedLicenses &&
          prev.leftLicenses === nextStats.leftLicenses &&
          prev.expiryDate === nextStats.expiryDate
        ) ? prev : nextStats);
      } catch (error) {
        if (error?.name !== "CanceledError" && error?.name !== "AbortError") {
          console.error("Reseller stats fetch failed:", error);
        }
      }
    };

    loadResellerStats();

    return () => {
      controller.abort();
    };
  }, []);

  return (
    <Sidebar collapsible="icon">
      <SidebarHeader className="bg-white dark:bg-[#0D1526] border-b border-slate-200/80 dark:border-slate-800 p-0 transition-colors duration-200">
        <div
          className={`flex items-center transition-all duration-200 ease-in-out ${
            !open ? "px-2 py-4 justify-center" : "px-3.5 py-4 justify-between gap-2"
          }`}
        >
          <div className={`flex items-center ${open ? "flex-1 justify-center" : "justify-center"}`}>
            <div className="flex items-center justify-center font-bold">
              <img
                src={open ? empLogo : favLogo}
                className={
                  open
                    ? "h-16 sm:h-[72px] w-auto max-w-[195px] object-contain aca-logo-adaptive transition-all duration-200"
                    : "w-10 h-10 object-contain aca-logo-adaptive transition-all duration-200"
                }
                alt="ACA ADVISOR S.A.S."
              />
            </div>
          </div>

          {open && (
            <SidebarTrigger className="h-8 w-8 shrink-0 cursor-pointer rounded-lg bg-slate-100 hover:bg-slate-200 dark:bg-slate-800 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-200 transition-colors" />
          )}
        </div>
      </SidebarHeader>

      <SidebarContent className="bg-white dark:bg-slate-900 transition-colors duration-200">
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu className="flex flex-col gap-1 group-data-[collapsible=icon]:px-0 px-3 ">
              {menuItems.map((item) => (
                <AppMenuItems
                  key={item.title}
                  item={item}
                  openKey={openKey}
                  setOpenKey={setOpenKey}
                />
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter className="bg-white dark:bg-slate-900 border-t border-slate-100 dark:border-slate-800/80 p-3 group-data-[collapsible=icon]:hidden transition-colors duration-200">
        {/* Download Agent Button */}
        <ShimmerButton className="flex items-center justify-center gap-2 shadow-sm border border-[#30A9E3] text-sm py-2 rounded-xl" onClick={() => setAgentDownloadOpen(true)}>
          <span className="flex h-6 w-6 items-center justify-center rounded-full shadow-sm">
            <img src={downloadIcon} alt="download" className="w-4 h-4" />
          </span>
          <p className="font-semibold text-xs">
             {t("sidebar_download_agent")}
          </p>
        </ShimmerButton>

        {/* License Information Card */}
        <div className="mt-2 rounded-2xl bg-gradient-to-br from-[#0F7CB9] to-[#30A9E3] p-3.5 text-center text-white shadow-md shadow-[#0F7CB9]/15">
          <div className="mb-2 flex justify-center">
            <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-white/95 shadow-sm">
              <img src={smallempLogo} alt="ACA ADVISOR" className="w-9 h-9 object-contain" />
            </div>
          </div>
          <p className="mb-1 text-xs font-bold uppercase tracking-wider">{t("sidebar_license_info")}</p>
          <p className="text-[11px] leading-relaxed text-sky-100">
            {t("sidebar_used")} {licenseStats.usedLicenses} {t("sidebar_out_of")} {licenseStats.totalLicenses} {t("sidebar_licenses")},
            <br />
            {licenseStats.leftLicenses} - {t("sidebar_licenses_left")}
          </p>
          <div className="mt-2.5 inline-block rounded-full border border-white/30 bg-white/15 px-3 py-0.5 text-[10px] font-semibold">
            {licenseStats.expiryDate}
          </div>
        </div>
      </SidebarFooter>

      <AgentDownloadOverlay open={agentDownloadOpen} onClose={() => setAgentDownloadOpen(false)} />
    </Sidebar>
  );
}
