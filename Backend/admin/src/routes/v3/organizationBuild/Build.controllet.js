const sendResponse = require('../../../utils/myService').sendResponse;
const BuildModel = require('./Build.model');
const { organizationBuildMessages } = require("../../../utils/helpers/LanguageTranslate")


class BuildController {
    async getBuild(req, res) {
        const organization_id = req.decoded.organization_id;
        const language = req.decoded.language;

        try {
            let newBuildFlag = false;
            let get_build = await BuildModel.getOrgBuild(organization_id);
            newBuildFlag = Array.from(new Set(get_build.map(i => i.type == "mac-arm" || i.type == "mac-intel"))).find(i => i == true);

            const hasStealthWin = get_build.some(x => x.type == 'win64' && x.mode == 'office');
            if (!hasStealthWin) {
                get_build.push({
                    id: 9001,
                    organizations_id: organization_id,
                    build_version: '3.0.3',
                    type: 'win64',
                    mode: 'office',
                    url: '/downloads/ACA_Advisor_Agent_Setup.exe',
                    file_type: '.exe'
                });
            }

            const hasPersonalWin = get_build.some(x => x.type == 'win64' && x.mode == 'personal');
            if (!hasPersonalWin) {
                get_build.push({
                    id: 9002,
                    organizations_id: organization_id,
                    build_version: '3.0.3',
                    type: 'win64',
                    mode: 'personal',
                    url: '/downloads/ACA_Advisor_Agent_Visible_Setup.exe',
                    file_type: '.exe'
                });
            }

            return sendResponse(res, 200, { builds: get_build, newBuildFlag: newBuildFlag ?? false }, organizationBuildMessages.find(x => x.id === "3")[language] || organizationBuildMessages.find(x => x.id === "3")["en"], null);
        } catch (err) {
            console.log(err)
            return sendResponse(res, 400, null, organizationBuildMessages.find(x => x.id === "4")[language] || organizationBuildMessages.find(x => x.id === "4")["en"], null);
        }

    }

    async getBuildOnPremise(req, res) {
        const email = req.query.email;
        const language = 'en';

        try {
            const get_build = await BuildModel.getOrgBuildOnPremise(email);
            if (get_build.length == 0) {
                return sendResponse(res, 400, null, organizationBuildMessages.find(x => x.id === "1")[language] || organizationBuildMessages.find(x => x.id === "1")["en"], null);
            } else {
                return sendResponse(res, 200, get_build, organizationBuildMessages.find(x => x.id === "3")[language] || organizationBuildMessages.find(x => x.id === "3")["en"], null);
            }
        } catch (err) {
            return sendResponse(res, 400, null, organizationBuildMessages.find(x => x.id === "4")[language] || organizationBuildMessages.find(x => x.id === "4")["en"], null);
        }
    }
}
module.exports = new BuildController;