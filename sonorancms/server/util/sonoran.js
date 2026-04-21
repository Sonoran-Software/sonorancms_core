let initialized = false;
let cmsServerId = 1;

const parseJsonMaybe = (value) => {
	if (typeof value !== "string" || value.trim() === "") {
		return value;
	}

	try {
		return JSON.parse(value);
	} catch {
		return value;
	}
};

exports("initializeCMS", (CommID, APIKey, serverId, apiUrl, debug_mode) => {
	void CommID;
	void APIKey;
	void apiUrl;
	void debug_mode;
	cmsServerId = serverId;

	if (initialized) {
		console.log("Sonoran CMS already initialized.");
		return;
	}

	initialized = true;
	console.log("Sonoran CMS v2 helper initialized.");
});

exports("checkCMSWhitelist", async (apiId, cb) => {
	try {
		exports.sonorancms.performApiRequest(
			{
				apiId,
				serverId: cmsServerId,
			},
			"VERIFY_WHITELIST",
			(result, ok) => {
				if (ok) {
					cb({
						success: true,
						reason: result,
					});
					return;
				}

				cb({
					success: false,
					error: parseJsonMaybe(result),
					backendError: true,
				});
			}
		);
	} catch (error) {
		cb({
			success: false,
			error,
			backendError: true,
		});
	}
});

exports("getFullWhitelist", async (cb) => {
	try {
		exports.sonorancms.performApiRequest(
			{
				serverId: cmsServerId,
			},
			"FULL_WHITELIST",
			(result, ok) => {
				if (!ok) {
					cb({
						success: false,
						error: parseJsonMaybe(result),
						backendError: true,
					});
					return;
				}

				const parsed = parseJsonMaybe(result);
				cb({
					success: true,
					data: Array.isArray(parsed) ? parsed : [],
				});
			}
		);
	} catch (error) {
		cb({
			success: false,
			error,
			backendError: true,
		});
	}
});
