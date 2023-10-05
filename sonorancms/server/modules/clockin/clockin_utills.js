
const fetch = require('node-fetch');

/**
 *
 * @param {string} message
 * @param  {errStack} args
 * @returns
 */
module.exports.errorLog = (message, ...args) => {
    return console.log(`^1[ERROR - Sonoran CMS ClockIn - ${new Date().toLocaleString()}] ${message}`, args + '^0');
}

/**
 *
 * @param {string} message
 * @returns
 */
module.exports.infoLog = (message) => {
    return console.log(`[INFO - Sonoran CMS ClockIn - ${new Date().toLocaleString()}] ${message}`);
}

/**
 *
 * @param {string} apiId
 * @param {boolean} forceClockIn
 * @returns {Promise}
 */
module.exports.clockPlayerIn = (apiId, forceClockIn) => {
    return new Promise(async (resolve, reject) => {
        exports.sonorancms.performApiRequest([{ "apiId": apiId, "forceClockIn": !!forceClockIn }], "CLOCK_IN_OUT", function (res) {
            res = JSON.parse(res)
            if (res) {
                resolve(res.completed);
            } else {
                reject('There was an error')
            }
        })
    });
}

/**
 *
 * @param {playerSource} source
 * @param {string} type
 * @returns {string}
 */
module.exports.getAppropriateIdentifier = (source, type) => {
    const identifiers = getPlayerIdentifiers(source);
    let properIdentifiers = {
        discord: '',
        steam: '',
        license: ''
    }
    identifiers.forEach((identifier) => {
        const splitIdentifier = identifier.split(':');
        const identType = splitIdentifier[0];
        const identId = splitIdentifier[1];
        switch (identType) {
            case 'discord':
                properIdentifiers.discord = identId;
                break;
            case 'steam':
                properIdentifiers.steam = identId;
                break;
            case 'license':
                properIdentifiers.license = identId;
                break;
        }
    });

    if (properIdentifiers[type] === '') {
        return null;
    } else {
        return properIdentifiers[type];
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
