import { useState } from "react";
import { useTranslation } from "react-i18next";
import empLogo      from "@/assets/emp.png";
import smallempLogo from "@/assets/smallemp.png";
import {
  Sidebar, SidebarContent, SidebarGroup, SidebarGroupContent,
  SidebarMenu, SidebarFooter, SidebarHeader, useSidebar, SidebarTrigger,
} from "@/components/ui/sidebar";
import { LayoutDashboard, HandCoins } from "lucide-react";
import AppMenuItems from "./AppMenuItems";

const getEmployeeMenuItems = (t) => [
  { title: t("dashboard"), url: "/employee/dashboard", icon: LayoutDashboard },
  { title: t("sidebar_time_claim"), url: "/employee/time-claim", icon: HandCoins },
];

export function EmployeeAppSidebar() {
  const { t } = useTranslation();
  const { open } = useSidebar();
  const [openKey, setOpenKey] = useState(null);
  const employeeMenuItems = getEmployeeMenuItems(t);

  return (
    <Sidebar collapsible="icon">
      <SidebarHeader className="bg-white dark:bg-[#0D1526] border-b border-slate-200/80 dark:border-slate-800 p-0 transition-colors duration-200">
        <div className={`flex items-center transition-all duration-200 ease-in-out ${!open ? "px-2 py-4 justify-center" : "px-3.5 py-4 justify-between gap-2"}`}>
          <div className={`flex items-center ${open ? "flex-1 justify-center" : "justify-center"}`}>
            <img
              src={open ? empLogo : smallempLogo}
              className={
                open
                  ? "h-16 sm:h-[72px] w-auto max-w-[195px] object-contain aca-logo-adaptive transition-all duration-200"
                  : "w-10 h-10 object-contain aca-logo-adaptive transition-all duration-200"
              }
              alt="ACA ADVISOR S.A.S."
            />
          </div>
          {open && (
            <SidebarTrigger className="h-8 w-8 shrink-0 cursor-pointer rounded-lg bg-slate-100 hover:bg-slate-200 dark:bg-slate-800 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-200 transition-colors" />
          )}
        </div>
      </SidebarHeader>

      <SidebarContent className="bg-white dark:bg-[#0D1526] transition-colors duration-200">
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu className="flex flex-col gap-1 group-data-[collapsible=icon]:px-0 px-3">
              {employeeMenuItems.map((item) => (
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

      <SidebarFooter className="bg-white dark:bg-[#0D1526] border-t border-slate-100 dark:border-slate-800/80 p-3 group-data-[collapsible=icon]:hidden transition-colors duration-200">
        <div className="rounded-2xl bg-gradient-to-br from-[#0F7CB9] to-[#30A9E3] p-3.5 text-center text-white shadow-md shadow-[#0F7CB9]/15">
          <div className="mb-2 flex justify-center">
            <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-white/95 shadow-sm">
              <img src={smallempLogo} alt="ACA ADVISOR" className="w-9 h-9 object-contain" />
            </div>
          </div>
          <p className="mb-1 text-xs font-bold uppercase tracking-wider">{t("sidebar_employee_portal")}</p>
          <p className="text-[11px] leading-relaxed text-sky-100">
            {t("sidebar_employee_portal_desc")}
          </p>
        </div>
      </SidebarFooter>
    </Sidebar>
  );
}
