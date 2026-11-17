'use strict';

const validator = require('./clock-in.validation');
const clockInModel = require('./clock-in.model');
const moment = require('moment-timezone');

class ClockInOutService {
    /*async record_Old(req, res, next) {
        try {
            const dataDto = await validator.validateClockInParams().validateAsync(req.body);
            let user = req.decoded;

            const employeeId = user.employee_id || user.id;
            const organizationId = user.organization_id || user.admin_id;

            if (employeeId) {
                if (dataDto.data.constructor === Array && dataDto.data.length > 0) {
                    let success = true;

                    for (let i = 0; i < dataDto.data.length; i++) {
                        let { startDate, endDate } = dataDto.data[i];
                        const { type, mode } = dataDto.data[i];
                        startDate = moment(startDate).tz('Africa/Bamako');
                        endDate = moment(endDate).tz('Africa/Bamako');
                        const duration = moment.duration(endDate.diff(startDate)).asSeconds();
                        const date = startDate.format('YYYY-MM-DD');

                        let [attendanceData] = await clockInModel.getUserAttendance(
                            date,
                            employeeId,
                            organizationId
                        );

                        if (!attendanceData) {
                            // attendanceData = await clockInModel.createAttendanceEntry(
                            //     date,
                            //     employeeId,
                            //     organizationId,
                            //     startDate.format('YYYY-MM-DD HH:mm:ss'),
                            //     endDate.format('YYYY-MM-DD HH:mm:ss')
                            // );
                            // attendanceData = { id: attendanceData.insertId };
                            return res.status(404).json({
                                code: 404,
                                error: 'Error in Attendance',
                                message: 'Attendance for this date is not available',
                                data: null
                            });
                        }

                        if (attendanceData) {
                            const curAttendanceId = attendanceData.id;
                            const curStartDate = startDate.format('YYYY-MM-DD HH:mm:ss');

                            // find
                            const dbTimeSheetData = await clockInModel.findCorrespondingTimeSheet(curAttendanceId, curStartDate, type, mode);

                            if (dbTimeSheetData && dbTimeSheetData.length > 0) { // update
                                await clockInModel.updateTimeSheet(dbTimeSheetData[0].id, endDate.format('YYYY-MM-DD HH:mm:ss'), duration);
                            } else { // insert
                                let timesheetEntryData = await clockInModel.insertInTimeSheet(
                                    attendanceData.id,
                                    startDate.format('YYYY-MM-DD HH:mm:ss'),
                                    endDate.format('YYYY-MM-DD HH:mm:ss'),
                                    type, mode, duration
                                );
                            }
                        } else {
                            success = false;
                            break;
                        }
                    }

                    if (success === true) return res.status(200).json({ code: 200, error: null, message: 'ClockIn/ClockOut data recorded', data: { status: 'updated' } });
                    else return res.status(422).json({ code: 422, error: 'Error in Attendance', message: 'Some error occured while upserting attendance id', data: null });
                } else return res.status(422).json({ code: 422, error: 'Error in params', message: 'Data should be passed in array', data: null });
            } else return res.status(422).json({ code: 422, error: 'EmployeeId is missing', message: 'Token does not contain employee id', data: null });
        } catch (err) {
            next(err);
        }
    }*/

    async record(req, res, next) {
        try {
            const dataDto = await validator.validateClockInParams().validateAsync(req.body);
            const employee_id = req.decoded.employee_id || req.decoded.id;
            const organization_id = req.decoded.organization_id || req.decoded.admin_id || 1;
            const userTz = req.decoded.timezone || 'America/Bogota';

            if (employee_id) {
                if (dataDto.data.constructor === Array && dataDto.data.length > 0) {

                    for (let i = 0; i < dataDto.data.length; i++) {
                        let { startDate, endDate, type, mode, reason } = dataDto.data[i];

                        const startUtc = moment.utc(startDate);
                        const curStartDate = startUtc.format('YYYY-MM-DD HH:mm:ss');
                        const localDate = startUtc.clone().tz(userTz).format('YYYY-MM-DD');
                        let duration = 0;
                        let curEndDate = null;

                        if (endDate && endDate !== '') {
                            const endUtc = moment.utc(endDate);
                            curEndDate = endUtc.format('YYYY-MM-DD HH:mm:ss');
                            duration = Math.max(0, Math.round(moment.duration(endUtc.diff(startUtc)).asSeconds()));
                        }

                        // Ensure employee_attendance row exists for this localDate
                        let [attendanceData] = await clockInModel.getUserAttendance(
                            localDate,
                            employee_id,
                            organization_id
                        );
                        let attendanceId = attendanceData ? attendanceData.id : null;
                        if (!attendanceId) {
                            const createdAtt = await clockInModel.createAttendanceEntry(
                                localDate,
                                employee_id,
                                organization_id,
                                curStartDate,
                                curEndDate || curStartDate
                            );
                            attendanceId = createdAtt ? createdAtt.insertId : null;
                        } else if (curEndDate) {
                            await clockInModel.updateAttendanceEndTime(attendanceId, curEndDate);
                        }

                        // Find existing timesheet entry by employee_id or attendance_id
                        const dbTimeSheetData = await clockInModel.findCorrespondingTimeSheetByEmpId(employee_id, curStartDate, type, mode, attendanceId);

                        if (dbTimeSheetData && dbTimeSheetData.length > 0) {
                            if (curEndDate) {
                                await clockInModel.updateTimeSheet(dbTimeSheetData[0].id, curEndDate, duration, attendanceId);
                            }
                        } else {
                            await clockInModel.insertInTimeSheetWithEmpId(
                                employee_id,
                                curStartDate,
                                curEndDate,
                                type, mode, duration, reason, attendanceId
                            );
                        }
                    }

                    return res.status(200).json({ code: 200, error: null, message: 'ClockIn/ClockOut data recorded', data: { status: 'updated' } });

                } else return res.status(422).json({ code: 422, error: 'Error in params', message: 'Data should be passed in array', data: null });
            } else return res.status(422).json({ code: 422, error: 'EmployeeId is missing', message: 'Token does not contain employee id', data: null });
        } catch (err) {
            next(err);
        }
    }

    async details(req, res, next) {
        try {
            const dataDto = await validator.validateDetailedClockInParams().validateAsync(req.body);
            const user = req.decoded;
            const userTz = user.timezone || 'America/Bogota';
            const startDate = moment(dataDto.startDate).tz(userTz).format('YYYY-MM-DD');
            const endDate = moment(dataDto.endDate).tz(userTz).format('YYYY-MM-DD');
            const employeeId = user.employee_id || user.id;

            if (employeeId) {
                let fetchedList = await clockInModel.getUserAttendanceDayWiseWithTimesheetData(startDate, endDate, employeeId);
                fetchedList = fetchedList.filter(item => item.timesheet_id !== null);

                if (fetchedList.length === 0) return res.status(404).json({ code: 404, error: 'No data found', message: 'Data not available', data: { count: 0, clockInList: fetchedList } });
                else return res.status(200).json({ code: 200, error: null, message: 'ClockIn/ClockOut data found', data: { count: fetchedList.length, clockInList: fetchedList } });
            } else return res.status(422).json({ code: 422, error: 'EmployeeId is missing', message: 'Token does not contain employee id', data: null });

        } catch (err) {
            next(err);
        }
    }
}

module.exports = new ClockInOutService;