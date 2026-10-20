let initialized = false;

const parseJsonMaybe = (value) => {
  if (typeof value !== "string" || value.trim() === "") return value;
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
  "TOO_MANY_ACCOUNTS",
  "INVALID_SERVER_ID",
  "SERVER_CONFIG_ERROR",
]);

const whitelistErrorReason = (value) => {
  const parsed = parseJsonMaybe(value);
  if (parsed && typeof parsed === "object") {
    return whitelistErrorReason(
      parsed.message ??
        parsed.reason ??
        parsed.error ??
        "Invalid whitelist response"
    );
  }
  return String(parsed ?? "Invalid whitelist response").trim();
};

// Rate limits and startup errors can suppress the Lua callback. Bound the wait,
// and ignore late replies so an outage cannot leave a join hanging or finish it twice.
const whitelistRequest = (data, requestType, cb) => {
  let complete = false;
  const finish = (result, ok) => {
    if (complete) return;
    complete = true;
    clearTimeout(timer);
    cb(result, ok);
  };
  const timer = setTimeout(
    () => finish("Whitelist request timed out", false),
    10000
  );
  try {
    exports.sonorancms.performApiRequest(data, requestType, finish);
  } catch (error) {
    finish(error.message, false);
  }
};

exports("initializeCMS", (CommID, APIKey, serverId, apiUrl, debug_mode) => {
  if (initialized) return;
  initialized = true;
  console.log("Sonoran CMS v2 helper initialized.");
});

exports("checkCMSWhitelist", (apiId, cb) => {
  // Startup refreshes can run before initializeCMS; always use the actual configured server.
  whitelistRequest(
    { apiId, serverId: exports.sonorancms.getWhitelistContext().serverId },
    "VERIFY_WHITELIST",
    (result, ok) => {
      if (ok && typeof result === "string" && result.trim() !== "") {
        cb({ success: true, reason: result });
        return;
      }
      const reason = whitelistErrorReason(result);
      const expected = whitelistDenialReasons.has(reason);
      cb({
        success: false,
        reason,
        backendError: !expected,
        denied:
          expected &&
          reason !== "INVALID_SERVER_ID" &&
          reason !== "SERVER_CONFIG_ERROR",
      });
    }
  );
});

exports("getFullWhitelist", (cb, snapshot = false) => {
  whitelistRequest(
    { serverId: exports.sonorancms.getWhitelistContext().serverId, snapshot },
    "FULL_WHITELIST",
    (result, ok) => {
      const parsed = parseJsonMaybe(result);
      const players = snapshot ? parsed?.players : parsed;
      const valid =
        ok &&
        (!snapshot || typeof parsed?.enabled === "boolean") &&
        Array.isArray(players) &&
        players.every(
          (player) =>
            Array.isArray(player?.apiIds) &&
            player.apiIds.every(
              (id) => typeof id === "string" && id.trim() !== ""
            )
        );
      // A malformed success is an outage, never an authoritative empty whitelist.
      if (!valid) {
        cb({
          success: false,
          backendError: true,
          error: "Invalid or unavailable whitelist snapshot",
        });
        return;
      }
      cb({
        success: true,
        data: players,
        ...(snapshot ? { enabled: parsed.enabled } : {}),
      });
    }
  );
});
