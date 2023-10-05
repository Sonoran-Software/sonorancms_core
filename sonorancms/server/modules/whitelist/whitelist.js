const utils = require("./whitelist_utils");
const luaConfig = LoadResourceFile(GetCurrentResourceName(), "/config.lua");
const cleanLuaConfig = luaConfig.replace(/--.*/g, '');
let activePlayers = {};
const config = {};
cleanLuaConfig.replace(/Config\.(\w+)\s*=\s*(.*?)(?=\n|$)/g, (match, key, value) => {
    config[key] = value.trim();
});
let apiKey = config.apiKey;
let apiIdType = config.apiIdType;

async function initialize() {
    TriggerEvent("sonorancms::RegisterPushEvent", "ACCOUNT_UPDATED", "sonoran_whitelist::rankupdate")
    await utils.sleep(2000)
    let backup = JSON.parse(
        LoadResourceFile(GetCurrentResourceName(), "/server/modules/whitelist/whitelist_backup.json")
    );
    utils.updateBackup();
    RegisterNetEvent('sonoran_whitelist::rankupdate')
    on(
        'sonoran_whitelist::rankupdate',
        async (data) => {
            const accountID = data.data.accId;
            if (activePlayers[accountID]) {
                let apiId;
                apiId = utils.getAppropriateIdentifier(
                    activePlayers[accountID],
                    apiIdType.toLowerCase()
                );
                if (!apiId)
                    return utils.errorLog(
                        `Could not find the correct API ID to cross check with the whitelist... Requesting type: ${apiIdType.toUpperCase()}`
                    );
                if (data.key === apiKey) {
                    exports.sonorancms.checkCMSWhitelist(apiId, function (whitelist) {
                        if (whitelist.success) {
                            utils.infoLog(
                                `After role update, ${data.data.accName} (${accountID}) is still whitelisted, username returned: ${JSON.stringify(whitelist.reason)} `
                            );
                        } else {
                            DropPlayer(activePlayers[accountID], 'After SonoranCMS role update, you were no longer whitelisted: ' + utils.apiMsgToEnglish(whitelist.reason.message))
                            utils.infoLog(
                                `After SonoranCMS role update ${data.data.accName} (${accountID}) was no longer whitelisted, reason returned: ${utils.apiMsgToEnglish(whitelist.reason.message)}`
                            );
                            activePlayers[accountID] = null
                        }
                    })
                }
            }
        }
    );
    on(
        "playerConnecting",
        async (name, setNickReason, deferrals) => {
            const src = global.source;
            let apiId;
            deferrals.defer();
            deferrals.update(
                "Grabbing API ID to check against the whitelist..."
            );
            apiId = utils.getAppropriateIdentifier(
                src,
                apiIdType.toLowerCase()
            );
            if (!apiId)
                return utils.errorLog(
                    `Could not find the correct API ID to cross check with the whitelist... Requesting type: ${apiIdType.toUpperCase()}`
                );
            deferrals.update("Checking whitelist...");
            utils.updateBackup();
            await exports.sonorancms.checkCMSWhitelist(apiId, function (whitelist) {
                if (whitelist.success) {
                    deferrals.done();
                    utils.infoLog(
                        `Successfully allowed ${name} (${apiId}) through whitelist, username returned: ${JSON.stringify(whitelist.reason)} `
                    );
                    exports.sonorancms.performApiRequest([{ "apiId": apiId, }], "GET_COM_ACCOUNT", function (data) {
                        activePlayers[data[0].accId] = src
                    })
                } else {
                    deferrals.done(
                        `Failed whitelist check: ${utils.apiMsgToEnglish(whitelist.reason.message)} \n\nAPI ID used to check: ${apiId}`
                    );
                    utils.infoLog(
                        `Denied ${name} (${apiId}) through whitelist, reason returned: ${utils.apiMsgToEnglish(whitelist.reason.message)}`
                    );
                }
            })
        }
    );
    setInterval(() => { utils.updateBackup() }, 1800000);
}

initialize();