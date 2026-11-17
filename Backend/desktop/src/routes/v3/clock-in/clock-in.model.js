'use strict';

const { format: formatSql } = require('mysql2');

const mySql = require('../../../database/MySqlConnection').getInstance();


class ClockInModel {
    constructor() {
        this.empAttendanceTable = 'employee_attendance';
        this.empTimeSheetTable = 'employee_timesheet';
        this.isTimeout = process.env.MYSQL_TIMEOUT === 'true';
        this.timeout = parseInt(process.env.MYSQL_TIMEOUT_INTERVAL);
    }

    getUserAttendance(date, employee_id, organization_id) {
        const query = `SELECT 
        id, employee_id, organization_id, date, start_time, end_time, created_at, updated_at 
        FROM ${this.empAttendanceTable} WHERE 
        employee_id = ? AND 
        date = ? AND organization_id = ? LIMIT 1`;
        const paramsArray = [employee_id, date, organization_id];
        const sql = formatSql(query, paramsArray);

        if (this.isTimeout) {
            return mySql.query({ sql, timeout: this.timeout });
        }

        return mySql.query(sql);
    }

    createAttendanceEntry(date, employee_id, organization_id, startDate, endDate) {
        const query = `
        INSERT INTO ${this.empAttendanceTable} (employee_id, organization_id, date, start_time, end_time) 
        VALUES (?, ?, ?, ?, ?)`;
        const paramsArray = [employee_id, organization_id, date, startDate, endDate];
        const sql = formatSql(query, paramsArray);

        if (this.isTimeout) {
            return mySql.query({ sql, timeout: this.timeout });
        }

        return mySql.query(sql);
    }

    findCorrespondingTimeSheet(attendanceId, startDate, type, mode) {
        const query = `
        SELECT id FROM ${this.empTimeSheetTable} WHERE 
        attendance_id = ? AND start_time = ? AND type = ? AND mode = ? LIMIT 1`;
        const paramsArray = [attendanceId, startDate, type, mode];
        const sql = formatSql(query, paramsArray);

        if (this.isTimeout) {
            return mySql.query({ sql, timeout: this.timeout });
        }

        return mySql.query(sql);
    }

    findCorrespondingTimeSheetByEmpId(employee_id, startDate, type, mode, attendanceId = null) {
        const query = `
        SELECT id FROM ${this.empTimeSheetTable} WHERE 
        (employee_id = ? OR (attendance_id IS NOT NULL AND attendance_id = ?)) AND start_time = ? AND type = ? AND mode = ? LIMIT 1`;
        const paramsArray = [employee_id, attendanceId, startDate, type, mode];
        const sql = formatSql(query, paramsArray);

        if (this.isTimeout) {
            return mySql.query({ sql, timeout: this.timeout });
        }

        return mySql.query(sql);
    }

    updateAttendanceEndTime(attendanceId, endDate) {
        const query = `UPDATE ${this.empAttendanceTable} SET end_time = GREATEST(end_time, ?) WHERE id = ?`;
        const paramsArray = [endDate, attendanceId];
        const sql = formatSql(query, paramsArray);

        if (this.isTimeout) {
            return mySql.query({ sql, timeout: this.timeout });
        }

        return mySql.query(sql);
    }

    insertInTimeSheet(attendanceId, startDate, endDate, type, mode, duration) {
        const query = `
        INSERT INTO ${this.empTimeSheetTable} (attendance_id, start_time, end_time, type, mode, duration) 
        VALUES (?, ?, ?, ?, ?, ?)`;
        const paramsArray = [attendanceId, startDate, endDate, type, mode, duration];
        const sql = formatSql(query, paramsArray);

        if (this.isTimeout) {
            return mySql.query({ sql, timeout: this.timeout });
        }

        return mySql.query(sql);
    }

    insertInTimeSheetWithEmpId(employee_id, startDate, endDate, type, mode, duration, reason, attendanceId = null) {
        endDate = endDate ? endDate : null;
        reason = reason ? reason : null;

        const query = `
        INSERT INTO ${this.empTimeSheetTable} (attendance_id, employee_id, start_time, end_time, type, mode, duration, reason) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)`;
        const paramsArray = [attendanceId, employee_id, startDate, endDate, type, mode, duration, reason];
        const sql = formatSql(query, paramsArray);

        if (this.isTimeout) {
            return mySql.query({ sql, timeout: this.timeout });
        }

        return mySql.query(sql);
    }

    updateTimeSheet(timeSheetId, endDate, duration, attendanceId = null) {
        const query = `UPDATE ${this.empTimeSheetTable} SET end_time = ?, duration = ?, attendance_id = COALESCE(attendance_id, ?) WHERE id = ?`;
        const paramsArray = [endDate, duration, attendanceId, timeSheetId];
        const sql = formatSql(query, paramsArray);

        if (this.isTimeout) {
            return mySql.query({ sql, timeout: this.timeout });
        }

        return mySql.query(sql);
    }

    getUserAttendanceDayWiseWithTimesheetData(startDate, endDate, employee_id) {
        const query = `
        SELECT ea.id, ea.date, ea.employee_id, et.id as timesheet_id, COALESCE(et.attendance_id, ea.id) as attendance_id, et.start_time, et.end_time, et.type, et.mode, et.duration 
        FROM ${this.empAttendanceTable} ea 
        LEFT JOIN ${this.empTimeSheetTable} et ON (et.attendance_id = ea.id OR (et.employee_id = ea.employee_id AND DATE(et.start_time) = ea.date))
        WHERE ea.date BETWEEN ? AND ? AND ea.employee_id = ?`;
        const paramsArray = [startDate, endDate, employee_id];
        const sql = formatSql(query, paramsArray);

        if (this.isTimeout) {
            return mySql.query({ sql, timeout: this.timeout });
        }

        return mySql.query(sql);
    }
}

module.exports = new ClockInModel;