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

const whitelistDenialReasons = new Set([
	"BLOCKED FOR WHITELIST",
	"NOT ALLOWED ON WHITELIST",
	"UNKNOWN_ACC_API_ID",
	"INVALID_SERVER_ID",
	"SERVER_CONFIG_ERROR",
]);

const normalizeErrorReason = (value) => {
	if (typeof value === "string") {
		return value.trim();
	}

	if (value && typeof value === "object") {
		return JSON.stringify(value);
	}

	return String(value);
};

const isExpectedWhitelistDenial = (value) => {
	const reason = normalizeErrorReason(value);
	return whitelistDenialReasons.has(reason);
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

				const reason = parseJsonMaybe(result);
				if (isExpectedWhitelistDenial(reason)) {
					cb({
						success: false,
						reason: normalizeErrorReason(reason),
					});
					return;
				}

				cb({
					success: false,
					error: reason,
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
