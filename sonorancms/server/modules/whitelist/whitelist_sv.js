const whiteListLuaConfig = LoadResourceFile(GetCurrentResourceName(), "./config.lua");
const whitelistCleanLuaConfig = whiteListLuaConfig.replace(/--.*/g, "");
let activePlayers = {};
const whiteListConfig = {};
whitelistCleanLuaConfig.replace(/Config\.(\w+)\s*=\s*(.*?)(?=\n|$)/g, (match, key, value) => {
	whiteListConfig[key] = value.trim();
});
let whiteListapiKey = whiteListConfig.whiteListapiKey;
let whiteListapiIdType = whiteListConfig.apiIdType;
const enabledConfig = JSON.parse(LoadResourceFile(GetCurrentResourceName(), "./server/modules/whitelist/whitelist_config.json"));

/**
 *
 * @param {string} message
 * @param  {errStack} args
 * @returns
 */
errorLog = (message, ...args) => {
	return console.log(`^1[ERROR - Sonoran CMS Whitelist - ${new Date().toLocaleString()}] ${message}`, args + "^0");
};

/**
 *
 * @param {string} message
 * @returns {string}
 */
infoLog = (message) => {
	return console.log(`[INFO - Sonoran CMS Whitelist - ${new Date().toLocaleString()}] ${message}`);
};

/**
 *
 * @param {int} subInt
 * @returns {string}
 */
subIntToName = (subInt) => {
	switch (subInt) {
		case 0:
			return "FREE";
		case 1:
			return "STARTER";
		case 2:
			return "STANDARD";
		case 3:
			return "PLUS";
		case 4:
			return "PRO";
		case 5:
			return "SONORANONE";
	}
};

/**
 *
 * @param {string} apiMsg
 * @returns {string}
 */
apiMsgToEnglish = (apiMsg) => {
	console.log(apiMsg);
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
};

// /**
//  *
//  * @param {int} ms
//  * @returns {Promise}
//  */
// sleep = (ms) => {
//     return new Promise(resolve => setTimeout(resolve, ms));
// }

/**
 *
 * returns {Promise}
 */
updateBackup = () => {
	exports.sonorancms.getFullWhitelist(function (fullWhitelist) {
		if (fullWhitelist.success) {
			const idArray = [];
			fullWhitelist.data.forEach((fW) => {
				idArray.push(...fW.apiIds);
			});
			backup = idArray;
			SaveResourceFile(GetCurrentResourceName(), "/server/modules/whitelist/whitelist_backup.json", JSON.stringify(backup));
		}
	});
};

exports("updateBackup", updateBackup);
exports('errorLog', errorLog);
exports('infoLog', infoLog);
exports('subIntToName', subIntToName);
exports('apiMsgToEnglish', apiMsgToEnglish);

async function initialize() {
	if (!enabledConfig?.enabled) return;
	TriggerEvent("sonorancms::RegisterPushEvent", "ACCOUNT_CREATED", () => {
		TriggerEvent("sonoran_whitelist::rankupdate");
	});
	await exports.sonorancms.sleep(2000);
	let backup = JSON.parse(LoadResourceFile(GetCurrentResourceName(), "/server/modules/whitelist/whitelist_backup.json"));
	exports.sonorancms.updateBackup();
	RegisterNetEvent("sonoran_whitelist::rankupdate");
	on("sonoran_whitelist::rankupdate", async (data) => {
		const accountID = data.data.accId;
		if (activePlayers[accountID]) {
			let apiId;
			apiId = exports.sonorancms.getAppropriateIdentifier(activePlayers[accountID], whiteListapiIdType.toLowerCase());
			if (!apiId)
				return exports.sonorancms.errorLog(
					`Could not find the correct API ID to cross check with the whitelist... Requesting type: ${whiteListapiIdType.toUpperCase()}`
				);
			if (data.key === whiteListapiKey) {
				exports.sonorancms.checkCMSWhitelist(apiId, function (whitelist) {
					if (whitelist.success) {
						exports.sonorancms.infoLog(
							`After role update, ${data.data.accName} (${accountID}) is still whitelisted, username returned: ${JSON.stringify(whitelist.reason)} `
						);
					} else {
						DropPlayer(
							activePlayers[accountID],
							"After SonoranCMS role update, you were no longer whitelisted: " + exports.sonorancms.apiMsgToEnglish(whitelist.reason.message)
						);
						exports.sonorancms.infoLog(
							`After SonoranCMS role update ${data.data.accName} (${accountID}) was no longer whitelisted, reason returned: ${exports.sonorancms.apiMsgToEnglish(
								whitelist.reason.message
							)}`
						);
						activePlayers[accountID] = null;
					}
				});
			}
		}
	});
	on("playerConnecting", async (name, setNickReason, deferrals) => {
		const src = global.source;
		let apiId;
		deferrals.defer();
		deferrals.update("Grabbing API ID to check against the whitelist...");
		apiId = exports.sonorancms.getAppropriateIdentifier(src, whiteListapiIdType.toLowerCase());
		if (!apiId)
			return exports.sonorancms.errorLog(
				`Could not find the correct API ID to cross check with the whitelist... Requesting type: ${whiteListapiIdType.toUpperCase()}`
			);
		deferrals.update("Checking whitelist...");
		exports.sonorancms.updateBackup();
		await exports.sonorancms.checkCMSWhitelist(apiId, function (whitelist) {
			if (whitelist.success) {
				deferrals.done();
				exports.sonorancms.infoLog(`Successfully allowed ${name} (${apiId}) through whitelist, username returned: ${JSON.stringify(whitelist.reason)} `);
				exports.sonorancms.performApiRequest([{ apiId: apiId }], "GET_COM_ACCOUNT", function (data) {
					activePlayers[data[0].accId] = src;
				});
			} else {
				deferrals.done(`Failed whitelist check: ${exports.sonorancms.apiMsgToEnglish(whitelist.reason.message)} \n\nAPI ID used to check: ${apiId}`);
				DropPlayer(src, "You are not whitelisted: " + exports.sonorancms.apiMsgToEnglish(whitelist.reason.message));
				exports.sonorancms.infoLog(`Denied ${name} (${apiId}) through whitelist, reason returned: ${exports.sonorancms.apiMsgToEnglish(whitelist.reason.message)}`);
			}
		});
	});
	setInterval(() => {
		exports.sonorancms.updateBackup();
	}, 1800000);
}

initialize();

