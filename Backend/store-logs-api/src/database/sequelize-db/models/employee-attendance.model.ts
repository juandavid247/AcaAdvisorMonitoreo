import { Injectable, Inject } from '@nestjs/common';
import { mysqlConstants } from '../providers/sequelize-db.constants';
import { EmployeeAttendanceEntity } from '../entities/employee-attendance';
import { EmployeeTimesheetEntity } from '../entities/employee-timesheet';
import { Op } from 'sequelize';

@Injectable()
export class EmployeeAttendanceModel {

    constructor(@Inject(mysqlConstants.employeeAttendanceRepo) private readonly tableRepo: typeof EmployeeAttendanceEntity) { }

    async getUserAttendanceDayWiseWithTimesheetData(startDate: string, endDate: string, employee_id: number): Promise<any> {
        return await this.tableRepo.findAll<EmployeeAttendanceEntity>({
            where: {
                employee_id,
                date: { [Op.between]: [startDate, endDate] }
            },
            attributes: ['id', 'date', 'employee_id'],
            include: [{
                model: EmployeeTimesheetEntity,
                attributes: ['id', 'attendance_id', 'start_time', 'end_time', 'type', 'mode', 'duration'],
                all: true
            }],
            raw: true,
            nest: true
        });
    }

    // async getUserAttendanceIdOnSingleDay(startDate: string, employee_id: number): Promise<any> {
    //     return await this.tableRepo.findOne<EmployeeAttendanceEntity>({
    //         where: {
    //             employee_id,
    //             date: startDate
    //         },
    //         attributes: ['id', 'date'],
    //         raw: true,
    //         nest: true
    //     });
    // }


    async getUserAttendanceIdOnSingleDayElseCreate(date: string, employee_id: number, organization_id: number, startDate: string, endDate: string): Promise<any> {
        return await this.tableRepo.findOrCreate<EmployeeAttendanceEntity>({
            where: {
                employee_id,
                date,
                organization_id
            },
            defaults: { start_time: startDate, end_time: endDate }
        });
    }

    async getLastInsertedAttendance(employee_id: number, date: string) {
        return await this.tableRepo.findOne<EmployeeAttendanceEntity>({
            where: {
                employee_id,
                date
            },
            order: [
                ['date', 'DESC']
            ]
        });
    }

    async getLastInsertedAttendanceLastInserted(employee_id: number, date: string) {
        if (date) {
            const byDate = await this.tableRepo.findOne<EmployeeAttendanceEntity>({
                where: {
                    employee_id,
                    date
                }
            });
            if (byDate) return byDate;
        }
        return await this.tableRepo.findOne<EmployeeAttendanceEntity>({
            where: {
                employee_id
            },
            order: [
                ['date', 'DESC']
            ]
        });
    }

    async insertAttendance(employee_id: number, organization_id: number, date: string, start_time: string, end_time: string, details: string) {
        const created = await this.tableRepo.create<EmployeeAttendanceEntity>({
            employee_id, organization_id, date, start_time, end_time, details
        });
        await this.syncTimesheet(created.id, employee_id, start_time, end_time);
        return created;
    }

    async syncTimesheet(attendance_id: number, employee_id: number, start_time: string, end_time: string) {
        try {
            if (!attendance_id) return;
            const sequelize = this.tableRepo.sequelize;
            if (!sequelize) return;
            await sequelize.query(
                `INSERT INTO employee_timesheet (attendance_id, employee_id, start_time, end_time, type, mode, duration)
                 SELECT :attendance_id, :employee_id, :start_time, :end_time, 1, 1, GREATEST(0, TIMESTAMPDIFF(SECOND, :start_time, :end_time))
                 FROM DUAL
                 WHERE NOT EXISTS (
                     SELECT 1 FROM employee_timesheet WHERE attendance_id = :attendance_id AND type = 1
                 )`,
                {
                    replacements: { attendance_id, employee_id, start_time, end_time }
                }
            );
            await sequelize.query(
                `UPDATE employee_timesheet
                 SET end_time = GREATEST(COALESCE(end_time, :end_time), :end_time),
                     duration = GREATEST(0, TIMESTAMPDIFF(SECOND, start_time, GREATEST(COALESCE(end_time, :end_time), :end_time))),
                     employee_id = COALESCE(employee_id, :employee_id)
                 WHERE attendance_id = :attendance_id AND type = 1`,
                {
                    replacements: { attendance_id, employee_id, end_time }
                }
            );
        } catch (err) {
            console.error('syncTimesheet error:', err.message);
        }
    }


    // getUserAttendanceIdOnSingleDayElseCreate(date: string, employee_id: number, organization_id: number, startDate: string, endDate: string): Promise<any> {
    //     return this.tableRepo.findOrCreate<EmployeeAttendanceEntity>({
    //         where: {
    //             employee_id,
    //             date,
    //             organization_id
    //         },
    //         defaults: { start_time: startDate, end_time: endDate }
    //     }).spread((item, created) => {
    //         return item;
    //     });
    // }
}