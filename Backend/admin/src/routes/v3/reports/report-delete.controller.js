const fs = require('fs');
const path = require('path');
const ReportActivityLogModel = require("./reportActivityLog/reportActivityLog.model");

class ReportDeleteController {
    
    /**
     * function to delete the file after they are download using link
     *
     * @function deleteFileAfterDownload
     * @memberof ReportDeleteController
     * @param {*} req
     * @param {*} res
     * @param {*} next
     * @returns
     */
    deleteFileAfterDownload (req,res, next) {
        let reqUrl;
        try {
            reqUrl = decodeURI(req.url);
        } catch {
            return res.status(400).json({ code: 400, message: 'Invalid URL' });
        }
        const rawFilename = reqUrl.substring(reqUrl.lastIndexOf('/') + 1).split('?')[0];
        const filename = path.basename(rawFilename);
        if (!filename || filename !== rawFilename || filename.includes('..') || filename.includes('\0')) {
            return res.status(403).json({ code: 403, message: 'Forbidden' });
        }
        const fileExt = filename.substring(filename.lastIndexOf('.') + 1);
        /** file ext to delete after download */
        if( fileExt.toLowerCase() == 'csv' || fileExt.toLowerCase() == 'xlsx') {
            const fileDist = path.resolve(__dirname.split('src')[0], 'public/temp');
            const filePath = path.resolve(fileDist, filename);
            if (!filePath.startsWith(fileDist + path.sep)) {
                return res.status(403).json({ code: 403, message: 'Forbidden' });
            }
            
            /** file not present call next */
            if (!fs.existsSync(filePath)) return next();
            
            res.download(filePath, filename, function(err){
                fs.unlink(filePath, (unlinkErr) => {
                    ReportActivityLogModel.updateReportActivity({ filename }, { is_downloaded:true });
                    if(!unlinkErr)  ReportActivityLogModel.updateReportActivity({ filename }, { stage:'downloaded', is_active: false, is_deleted: true });
                });
            });
        } else {
            next()
        }
    }
}

module.exports = new ReportDeleteController;