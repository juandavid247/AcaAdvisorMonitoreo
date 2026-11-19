import apiService from "@/services/api.service";
import moment from "moment-timezone";
import { exportToCsv, exportToPdf } from "@/services/dlp.service";

const mapRow = (log) => {
    const tz = log.timezone || "America/Bogota";
    const startMoment = log.start ? moment.utc(log.start).tz(tz) : null;

    return {
        _id: log._id,
        title: log.title || "-",
        type: log.type || "11",
        description: log.description || "-",
        employeeId: log.employee_id,
        computer: log.computer || "-",
        eventDate: startMoment ? startMoment.format("YYYY-MM-DD") : (log.date || "-"),
        eventTime: startMoment ? startMoment.format("HH:mm:ss") : "-",
        start: startMoment ? startMoment.format("DD-MM-YYYY / HH:mm:ss") : "-",
        date: log.date || "-",
        fullName: log.full_name || "-",
        department: log.departament || "-",
        location: log.location || "-",
        timezone: tz,
    };
};

const buildUrl = (filters) => {
    const start = filters.startDate || moment().format("YYYY-MM-DD");
    const end = filters.endDate || moment().format("YYYY-MM-DD");

    let url = `/system-logs?startDate=${start}&endDate=${end}&limit=${filters.limit}&offset=${filters.skip}&type=11`;

    if (filters.employeeId && filters.employeeId !== "all") url += `&employee_id=${filters.employeeId}`;
    if (filters.locationId && filters.locationId !== "all") url += `&location_id=${filters.locationId}`;
    if (filters.departmentId && filters.departmentId !== "all") url += `&department_id=${filters.departmentId}`;
    if (filters.searchText) url += `&search_text=${encodeURIComponent(filters.searchText)}`;
    if (filters.sortName) url += `&sort_name=${filters.sortName}`;
    if (filters.sortOrder) url += `&sort_order=${filters.sortOrder}`;

    return url;
};

export const fetchLogs = async (filters) => {
    try {
        const { data } = await apiService.apiInstance.get(buildUrl(filters));
        const docs = data?.data?.docs ?? [];
        const totalDocs = data?.data?.totalDocs ?? 0;
        return { rows: (Array.isArray(docs) ? docs : []).map(mapRow), totalDocs };
    } catch (error) {
        console.error("Print Logs API Error:", error);
        return { rows: [], totalDocs: 0 };
    }
};

export const fetchExport = async (filters) => {
    try {
        const { data } = await apiService.apiInstance.get(
            buildUrl({ ...filters, skip: 0, limit: 50000 })
        );
        const docs = data?.data?.docs ?? [];
        return (Array.isArray(docs) ? docs : []).map(mapRow);
    } catch (error) {
        console.error("Print Logs Export Error:", error);
        return [];
    }
};

const HEADERS = ["Employee Name", "Department", "Location", "Computer", "Event Date", "Event Time", "Description"];
const buildRow = (r) => [r.fullName, r.department, r.location, r.computer, r.eventDate, r.eventTime, r.description];

export const exportCsv = (rows, dateRange) =>
    exportToCsv({
        rows,
        headers: HEADERS,
        buildRow,
        sheetName: "Print Logs",
        fileName: `Print_Logs_${dateRange}.xlsx`,
    });

export const exportPdf = (rows, dateRange) =>
    exportToPdf({
        rows,
        headers: HEADERS,
        buildRow,
        title: "Print Activity Logs",
        fileName: `Print_Logs_${dateRange}.pdf`,
        dateRange,
    });
