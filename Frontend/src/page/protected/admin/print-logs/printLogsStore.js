import { createDlpStore } from "@/hooks/useDlpStore";
import { fetchLogs, fetchExport, exportCsv, exportPdf } from "./service";

export const usePrintLogsStore = createDlpStore({
    name: "Print Logs",
    fetchLogs,
    fetchExport,
    exportCsv,
    exportPdf,
});
