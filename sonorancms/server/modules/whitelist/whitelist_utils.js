const fetch = require('node-fetch');

/**
 *
 * @param {string} message
 * @param  {errStack} args
 * @returns
 */
module.exports.errorLog = (message, ...args) => {
    return console.log(`^1[ERROR - Sonoran CMS Whitelist - ${new Date().toLocaleString()}] ${message}`, args + '^0');
}

/**
 *
 * @param {string} message
 * @returns {string}
 */
module.exports.infoLog = (message) => {
    return console.log(`[INFO - Sonoran CMS Whitelist - ${new Date().toLocaleString()}] ${message}`);
}

/**
 *
 * @param {int} subInt
 * @returns {string}
 */
module.exports.subIntToName = (subInt) => {
    switch (subInt) {
        case 0:
            return 'FREE';
        case 1:
            return 'STARTER';
        case 2:
            return 'STANDARD';
        case 3:
            return 'PLUS';
        case 4:
            return 'PRO';
        case 5:
            return 'SONORANONE';
    }
}

/**
 *
 * @param {string} apiMsg
 * @returns {string}
 */
module.exports.apiMsgToEnglish = (apiMsg) => {
    console.log(apiMsg)
    switch (apiMsg) {
        case "UNKNOWN_ACC_API_ID":
            return "unable to find a valid account with the provided API ID and account ID";
        case "INVALID_SERVER_ID":
            return "an invalid server ID was provided, please check your config and try again";
        case "SERVER_CONFIG_ERROR":
            return "an unexpected error occured while trying to retrieve the server's info";
        case "BLOCKED FOR WHITELIST":
            return "this user has a Sonoran CMS role that is preventing them from joining the server";
        case "NOT ALLOWED ON WHITELIST":
            return "this user does not have a Sonoran CMS with whitelist permissions";
    }
}

/**
 *
 * @param {int} ms
 * @returns {Promise}
 */
module.exports.sleep = (ms) => {
    return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 *
 * returns {Promise}
 */
module.exports.updateBackup = () => {
    exports.sonorancms.getFullWhitelist(function (fullWhitelist) {
        if (fullWhitelist.success) {
            const idArray = [];
            fullWhitelist.data.forEach((fW) => {
                idArray.push(...fW.apiIds);
            });
            backup = idArray;
            SaveResourceFile(
                GetCurrentResourceName(),
                "/server/modules/whitelist/whitelist_backup.json",
                JSON.stringify(backup)
            );
        }
    });
}

/**
 *
 * @param {playerSource} sourcePlayer
 * @param {string} type
 * @returns {string}
 */
module.exports.getAppropriateIdentifier = (sourcePlayer, type) => {
    const identifiers = getPlayerIdentifiers(sourcePlayer);
    let properIdentifiers = {
        discord: "",
        steam: "",
        license: ""
    };
    identifiers.forEach((identifier) => {
        const splitIdentifier = identifier.split(":");
        const identType = splitIdentifier[0];
        const identId = splitIdentifier[1];
        switch (identType) {
            case "discord":
                properIdentifiers.discord = identId;
                break;
            case "steam":
                properIdentifiers.steam = identId;
                break;
            case "license":
                properIdentifiers.license = identId;
                break;
        }
    });

    if (properIdentifiers[type] === "") {
        return null;
    } else {
        return properIdentifiers[type];
    }
}
