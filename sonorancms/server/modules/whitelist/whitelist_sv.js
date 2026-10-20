(() => {
  const fs = require("fs");
  const path = require("path");
  const resource = GetCurrentResourceName();
  const directory = "server/modules/whitelist/";
  const config = JSON.parse(
    LoadResourceFile(resource, directory + "whitelist_config.json") ||
      LoadResourceFile(resource, directory + "whitelist_config.dist.json")
  );
  if (!config?.enabled) return;

  let context;
  const backupFile = path.join(
    GetResourcePath(resource),
    directory,
    "whitelist_backup.json"
  );
  const log = (message) => console.log(`[Sonoran CMS Whitelist] ${message}`);
  const validIds = (ids) =>
    Array.isArray(ids) &&
    ids.every((id) => typeof id === "string" && id.trim() !== "");
  let backup = null;
  let backupRevision = 0;
  let refresh = null;
  let nextJoinRefreshAt = 0;

  // Cross-runtime exports are ready after the first scheduler tick. Register joins immediately,
  // but wait for the real Lua configuration before reading or writing a server-scoped backup.
  const ready = new Promise((resolve) => setTimeout(resolve, 0)).then(() => {
    context = exports.sonorancms.getWhitelistContext();
    try {
      const saved = JSON.parse(
        LoadResourceFile(resource, directory + "whitelist_backup.json")
      );
      // Never apply another community/server's rules, or infer disabled mode from an empty ID list.
      if (
        saved?.version === 1 &&
        typeof saved.enabled === "boolean" &&
        validIds(saved.apiIds) &&
        Number.isFinite(Date.parse(saved.updatedAt)) &&
        Object.keys(context).every((key) => saved[key] === context[key])
      )
        backup = saved;
      else if (saved)
        log(
          "Ignoring an old or mismatched whitelist backup; a successful CMS sync is required."
        );
    } catch {
      log("No readable whitelist backup; a successful CMS sync is required.");
    }
  });

  function saveBackup(next) {
    backup = next;
    backupRevision++;
    try {
      // Replace the JSON only after the full write succeeds. A failed write leaves the previous file intact.
      fs.writeFileSync(
        backupFile + ".tmp",
        JSON.stringify(next, null, 2),
        "utf8"
      );
      fs.renameSync(backupFile + ".tmp", backupFile);
    } catch (error) {
      log(
        `Could not save whitelist backup; the current in-memory copy is still available: ${error.message}`
      );
    }
  }

  function updateBackup(force = false) {
    if (refresh) return refresh;
    // Share recent attempts across joins (including failures) instead of hitting the 15/minute snapshot limit.
    if (!force && Date.now() < nextJoinRefreshAt)
      return Promise.resolve(backup);
    nextJoinRefreshAt = Date.now() + 30000;
    const revision = backupRevision;
    refresh = new Promise((resolve) => {
      exports.sonorancms.getFullWhitelist((result) => {
        if (
          !result?.success ||
          typeof result.enabled !== "boolean" ||
          !Array.isArray(result.data) ||
          !result.data.every((player) => validIds(player?.apiIds))
        ) {
          log(
            "CMS snapshot unavailable; keeping the last good whitelist backup."
          );
          resolve(null);
          return;
        }
        // A full-list request must not overwrite a newer individual allow/deny decision.
        if (revision !== backupRevision) {
          resolve(null);
          return;
        }
        const next = {
          version: 1,
          ...context,
          enabled: result.enabled,
          updatedAt: new Date().toISOString(),
          apiIds: [...new Set(result.data.flatMap((player) => player.apiIds))],
        };
        saveBackup(next);
        resolve(next);
      }, true);
    })
      .catch((error) => {
        log(`Could not refresh whitelist backup: ${error.message}`);
        return null;
      })
      .finally(() => {
        refresh = null;
      });
    return refresh;
  }

  function playerIdentifier(src) {
    const id = exports.sonorancms.getAppropriateIdentifier(
      src,
      context.apiIdType
    );
    return typeof id === "string" && id !== "NOT FOUND" && id.trim() !== ""
      ? id
      : null;
  }

  function cachedAllows(apiId) {
    return (
      backup !== null &&
      (!backup.enabled || (apiId !== null && backup.apiIds.includes(apiId)))
    );
  }

  function rememberDecision(apiId, allow) {
    if (allow && backup?.enabled === false) return;
    const ids = new Set(backup?.apiIds || []);
    if (allow) ids.add(apiId);
    else ids.delete(apiId);
    if (
      backup?.enabled === true &&
      ids.size === backup.apiIds.length &&
      backup.apiIds.every((id) => ids.has(id))
    )
      return;
    // Explicit online denials always win over cached membership and cached disabled mode.
    saveBackup({
      version: 1,
      ...context,
      enabled: true,
      updatedAt: new Date().toISOString(),
      apiIds: [...ids],
    });
  }

  const check = (apiId) =>
    new Promise((resolve) =>
      exports.sonorancms.checkCMSWhitelist(apiId, resolve)
    );
  const outageReason = () =>
    backup
      ? "CMS is unavailable and you are not in this server's saved whitelist."
      : "CMS is unavailable and this server has no valid whitelist backup. Please try again later.";

  on("playerConnecting", async (name, setKickReason, deferrals) => {
    const src = source;
    let apiId = null;
    let reason;
    deferrals.defer();
    await exports.sonorancms.sleep(0);
    deferrals.update("Checking CMS whitelist...");
    try {
      await ready;
      // Fetch explicit enabled/disabled state before requiring a player identifier.
      if (!backup || !backup.enabled) await updateBackup();
      if (backup?.enabled !== false) {
        apiId = playerIdentifier(src);
        if (!apiId) {
          // A recently disabled whitelist must also stop requiring identifiers.
          await updateBackup();
          if (backup?.enabled !== false)
            reason = `A ${context.apiIdType} identifier is required to check this server's CMS whitelist.`;
        } else {
          const result = await check(apiId);
          if (result?.success) {
            rememberDecision(apiId, true);
          } else if (result?.backendError) {
            if (!cachedAllows(apiId)) reason = outageReason();
          } else {
            if (result?.denied) rememberDecision(apiId, false);
            reason = `CMS whitelist denied access: ${
              result?.reason || "Unknown whitelist denial"
            }`;
          }
        }
      }
    } catch (error) {
      log(`Whitelist check failed: ${error.message}`);
      if (!cachedAllows(apiId)) reason = outageReason();
    }
    // FiveM requires a tick between deferral operations, including locally cached decisions.
    await exports.sonorancms.sleep(0);
    deferrals.done(reason);
    log(
      `${reason ? "Denied" : "Allowed"} ${name}${reason ? ": " + reason : ""}`
    );
  });

  let rechecking = false;
  let recheckPending = false;
  // The core forwards authenticated CMS account updates locally; this is deliberately not a net event.
  async function recheckPlayers() {
    recheckPending = true;
    if (rechecking) return;
    rechecking = true;
    try {
      // An update arriving during a request gets another pass instead of being dropped.
      do {
        recheckPending = false;
        await ready;
        const current = await updateBackup(true);
        if (current?.enabled === false) continue;
        for (const player of exports.sonorancms.jsGetPlayers()) {
          const apiId = playerIdentifier(player);
          if (!apiId) {
            if (current?.enabled && GetPlayerName(player))
              DropPlayer(
                player,
                `CMS whitelist requires a ${context.apiIdType} identifier.`
              );
            continue;
          }
          if (current?.apiIds.includes(apiId)) continue;
          const result = await check(apiId);
          // An unavailable API is never evidence that a connected player lost access.
          if (result?.backendError) break;
          if (result?.success) rememberDecision(apiId, true);
          else if (result?.denied) {
            rememberDecision(apiId, false);
            if (GetPlayerName(player) && playerIdentifier(player) === apiId) {
              DropPlayer(
                player,
                `CMS whitelist access revoked: ${result.reason}`
              );
            }
          }
        }
      } while (recheckPending);
    } catch (error) {
      log(`Could not recheck whitelist after account update: ${error.message}`);
    } finally {
      rechecking = false;
    }
  }
  on("sonoran_whitelist::rankupdate", recheckPlayers);

  const refreshWhenReady = () =>
    ready
      .then(() => updateBackup(true))
      .catch((error) =>
        log(`Whitelist initialization failed: ${error.message}`)
      );
  refreshWhenReady();
  // Revisit deferred revocations when CMS recovers, without repeatedly checking listed players.
  setInterval(recheckPlayers, 5 * 60 * 1000);
})();
