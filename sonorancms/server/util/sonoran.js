const Sonoran = require("@sonoransoftware/sonoran.js");

let instance;
exports("initializeCMS", (CommID, APIKey, serverId, apiUrl, debug_mode) => {
	apiUrl = apiUrl.replace(/\/$/, "");
	try {
		instance = new Sonoran.Instance({
			communityId: CommID,
			apiKey: APIKey,
			serverId: serverId,
			product: Sonoran.productEnums.CMS,
			cmsApiUrl: apiUrl,
			debug: debug_mode,
		});
	} catch (err) {
		console.log(`Sonoran CMS Setup Unsuccessfully! Error provided: ${err}`);
	}

	instance.on("CMS_SETUP_SUCCESSFUL", () => {
		console.log("ready to initialize");
	});

	instance.on("CMS_SETUP_UNSUCCESSFUL", (err) => {
		console.log(`Sonoran CMS Setup Unsuccessfully! Error provided: ${err}`);
	});

	exports("checkCMSWhitelist", (apiId, cb) => {
		try {
			instance.cms.verifyWhitelist(apiId).then((whitelist) => {
				cb(whitelist);
			});
		} catch (error) {
			cb({ success: false, error: error });
		}
	});

	exports("getFullWhitelist", (cb) => {
		try {
			instance.cms.getFullWhitelist().then((fullWhitelist) => {
				cb(fullWhitelist);
			});
		} catch (error) {
			cb({ success: false, error: error });
		}
	});
});
