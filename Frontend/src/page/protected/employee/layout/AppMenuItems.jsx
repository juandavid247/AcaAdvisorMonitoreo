import {
  SidebarMenuButton, SidebarMenuItem, SidebarMenuSub,
  SidebarMenuSubButton, SidebarMenuSubItem,
} from "@/components/ui/sidebar";
import { NavLink, useLocation } from "react-router-dom";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { ChevronRight } from "lucide-react";

const AppMenuItems = ({ item, openKey, setOpenKey }) => {
  const { pathname } = useLocation();
  const isOpen = openKey === item.title;
  const isChildActive = item.children?.some((c) => c.url === pathname) || false;

  if (!item.children) {
    return (
      <SidebarMenuItem>
        <SidebarMenuButton
          asChild
          tooltip={item.title}
          className="relative my-[2px] h-11 hover:bg-slate-100/70 dark:hover:bg-slate-800/60 rounded-xl transition-all duration-200"
        >
          <NavLink
            to={item.url}
            className={({ isActive }) =>
              `flex w-full items-center gap-3 px-3 rounded-xl transition-colors duration-200 ${isActive ? "bg-[#E0F2FE]/60 dark:bg-slate-800/80" : "hover:bg-slate-100/60 dark:hover:bg-slate-800/50"}`
            }
          >
            {({ isActive }) => (
              <>
                <item.icon className={`h-5 w-5 shrink-0 transition-colors duration-200 ${isActive ? "text-[#0F7CB9] dark:text-[#38BDF8]" : "text-slate-500 dark:text-slate-300"}`} />
                <span className={`text-[15px] transition-colors duration-200 ${isActive ? "font-bold text-[#0F7CB9] dark:text-[#7DD3FC]" : "font-medium text-slate-700 dark:text-slate-100 hover:text-[#0F7CB9] dark:hover:text-white"}`}>
                  {item.title}
                </span>
                {isActive && (
                  <div className="absolute right-0 top-1/2 h-6 w-[3px] -translate-y-1/2 rounded-l-md bg-[#30A9E3] group-data-[collapsible=icon]:hidden" />
                )}
              </>
            )}
          </NavLink>
        </SidebarMenuButton>
      </SidebarMenuItem>
    );
  }

  return (
    <Collapsible open={isOpen} onOpenChange={(o) => setOpenKey(o ? item.title : null)} className="group/collapsible">
      <SidebarMenuItem>
        <CollapsibleTrigger asChild>
          <SidebarMenuButton
            tooltip={item.title}
            className={`my-[2px] h-11 transition-all duration-200 hover:bg-slate-50 px-3 ${isChildActive ? "bg-slate-50/50" : ""}`}
          >
            <item.icon className={`h-5 w-5 shrink-0 ${isChildActive ? "text-[#1B2559]" : "text-[#cbd5e1]"}`} />
            <span className={`text-[15px] ${isChildActive ? "font-bold text-[#1B2559]" : "font-medium text-[#A3AED0]"}`}>{item.title}</span>
            <ChevronRight className="ml-auto h-4 w-4 shrink-0 transition-transform duration-200 group-data-[state=open]/collapsible:rotate-90 group-data-[collapsible=icon]:hidden" />
          </SidebarMenuButton>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <SidebarMenuSub className="pl-6 border-l border-slate-200 ml-4 py-1 flex flex-col gap-1">
            {item.children.map((child) => (
              <SidebarMenuSubItem key={child.title}>
                <SidebarMenuSubButton asChild className="h-9">
                  <NavLink
                    to={child.url}
                    className={({ isActive }) =>
                      `relative flex items-center px-3 w-full transition-all duration-200 ${isActive ? "font-bold text-[#1B2559]" : "font-medium text-[#A3AED0] hover:text-[#1B2559]"}`
                    }
                  >
                    {({ isActive }) => (
                      <>
                        <span className="text-[12px]">{child.title}</span>
                        {isActive && <div className="absolute right-0 top-1/2 h-5 w-[3px] -translate-y-1/2 rounded-l-md bg-[#1B2559]" />}
                      </>
                    )}
                  </NavLink>
                </SidebarMenuSubButton>
              </SidebarMenuSubItem>
            ))}
          </SidebarMenuSub>
        </CollapsibleContent>
      </SidebarMenuItem>
    </Collapsible>
  );
};

export default AppMenuItems;
