import React from "react";
import { useTranslation } from "react-i18next";
import { FileText } from "lucide-react";

const Footer = ({ show }) => {
  const { t } = useTranslation();
  if (!show) return null;

  return (
    <footer className="w-full bg-slate-100 dark:bg-[#0D1526] border-t border-slate-200/80 dark:border-slate-800/80 px-6 py-3.5 flex flex-col-reverse sm:flex-row gap-2 items-center justify-between mt-auto transition-colors duration-200">
      <div className="text-slate-500 dark:text-slate-400 text-[11px] sm:text-xs font-medium">
        © {new Date().getFullYear()} <span className="font-semibold text-[#0F7CB9] dark:text-[#38BDF8]">ACA ADVISOR S.A.S.</span> • {t("footer_all_rights") || "Todos los derechos reservados."}
      </div>

      {/* <button className="flex items-center gap-2 bg-[#0061ff] hover:bg-[#0051d5] text-white text-xs 2xl:px-2 px-4 py-2 rounded-lg transition-colors duration-200 font-medium">
        <FileText size={18} />
        <span>Download Report</span>
      </button> */}
    </footer>
  );
};

export default Footer;
