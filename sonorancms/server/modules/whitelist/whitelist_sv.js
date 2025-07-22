const whiteListLuaConfig = LoadResourceFile(
  GetCurrentResourceName(),
  "./config.lua"
);
const whitelistCleanLuaConfig = whiteListLuaConfig.replace(
  /--.*(?:\r?\n|$)/g,
  ""
);
const regexPattern =
  /Config\.(\w+)\s*=\s*(?:'([^']*)'|"([^"]*)"|(.*?))(?=\s*(?:\-\-|\n|$))/g;
let activePlayers = {};
const whiteListConfig = {};
whitelistCleanLuaConfig.replace(regexPattern, (match, key, value) => {
  whiteListConfig[key] = value?.trim();
});
let whiteListapiKey = whiteListConfig.APIKey;
let whiteListapiIdType = whiteListConfig.apiIdType;
const enabledConfig = JSON.parse(
  LoadResourceFile(
    GetCurrentResourceName(),
    "./server/modules/whitelist/whitelist_config.json"
  )
);

/**
 *
 * @param {string} message
 * @param  {errStack} args
 * @returns
 */
let errorLog = (message, ...args) => {
  return console.log(
    `^1[ERROR - Sonoran CMS Whitelist - ${new Date().toLocaleString()}] ${message}`,
    args + "^0"
  );
};

/**
 *
 * @param {string} message
 * @returns {string}
 */
let infoLog = (message) => {
  return console.log(
    `[INFO - Sonoran CMS Whitelist - ${new Date().toLocaleString()}] ${message}`
  );
};

/**
 *
 * @param {int} subInt
 * @returns {string}
 */
let subIntToName = (subInt) => {
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
let apiMsgToEnglish = (apiMsg) => {
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
    default:
      return `unknown whitelist error: ${apiMsg}`;
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
let updateBackup = () => {
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
};

/**
 *
 * @param {string} apiId
 * @returns {boolean}
 */
let checkBackup = (apiId) => {
  const backup = JSON.parse(
    LoadResourceFile(
      GetCurrentResourceName(),
      "/server/modules/whitelist/whitelist_backup.json"
    )
  );
  return backup.includes(apiId);
};

/**
 * @param {string} source
 * @returns {string}
 */
async function findPlayerBySource(source) {
  for (let accId in activePlayers) {
    if (activePlayers[accId] === source) {
      return accId;
    }
  }
  return null;
}

/**
 * @param {string} apiId
 * @param {string} src
 * @returns {Promise}
 */
let addActivePlayer = async (apiId, src) => {
  try {
    exports.sonorancms.performApiRequest(
      [{ apiId: apiId }],
      "GET_COM_ACCOUNT",
      function (data) {
        data = JSON.parse(data);
        activePlayers[data[0]?.accId] = src;
      }
    );
  } catch (err) {
    errorLog(
      `Error adding active player ${src} to activePlayers cache: ${err}`
    );
  }
};

async function initialize() {
  if (!enabledConfig?.enabled) return;
  TriggerEvent("sonorancms::RegisterPushEvent", "ACCOUNT_CREATED", () => {
    TriggerEvent("sonoran_whitelist::rankupdate");
  });
  await exports.sonorancms.sleep(2000);
  let backup = JSON.parse(
    LoadResourceFile(
      GetCurrentResourceName(),
      "/server/modules/whitelist/whitelist_backup.json"
    )
  );
  updateBackup();
  RegisterNetEvent("sonoran_whitelist::rankupdate");
  on("sonoran_whitelist::rankupdate", async (data) => {
    const accountID = data.data.accId;
    if (activePlayers[accountID]) {
      let apiId;
      apiId = exports.sonorancms.getAppropriateIdentifier(
        activePlayers[accountID],
        whiteListapiIdType.toLowerCase()
      );
      if (!apiId)
        return errorLog(
          `Could not find the correct API ID to cross check with the whitelist... Requesting type: ${whiteListapiIdType.toUpperCase()}`
        );
      if (data.key === whiteListapiKey) {
        exports.sonorancms.checkCMSWhitelist(apiId, function (whitelist) {
          if (whitelist.success) {
            infoLog(
              `After role update, ${
                data.data.accName
              } (${accountID}) is still whitelisted, username returned: ${JSON.stringify(
                whitelist.reason
              )} `
            );
          } else {
            DropPlayer(
              activePlayers[accountID],
              "After SonoranCMS role update, you were no longer whitelisted: " +
                apiMsgToEnglish(whitelist.reason)
            );
            infoLog(
              `After SonoranCMS role update ${
                data.data.accName
              } (${accountID}) was no longer whitelisted, reason returned: ${apiMsgToEnglish(
                whitelist.reason
              )}`
            );
            activePlayers[accountID] = null;
          }
        });
      }
    }
  });
  on("playerConnecting", async (name, setNickReason, deferrals) => {
    const src = source;
    let apiId;
    deferrals.defer();
    deferrals.update("Grabbing API ID to check against the whitelist...");
    apiId = exports.sonorancms.getAppropriateIdentifier(
      src,
      whiteListapiIdType.toLowerCase()
    );
    if (!apiId)
      return errorLog(
        `Could not find the correct API ID to cross check with the whitelist... Requesting type: ${whiteListapiIdType.toUpperCase()}`
      );
    deferrals.update("Checking whitelist...");
    updateBackup();
    try {
      await exports.sonorancms.checkCMSWhitelist(
        apiId,
        async function (whitelist) {
          if (whitelist?.success) {
            deferrals.done();
            infoLog(
              `Successfully allowed ${name} (${apiId}) through whitelist, username returned: ${JSON.stringify(
                whitelist.reason
              )} `
            );
          } else if (whitelist?.backendError) {
            let backupWhitelisted = checkBackup(apiId);
            if (backupWhitelisted) {
              deferrals.done();
              infoLog(
                `Successfully allowed ${name} (${apiId}) through whitelist, ${whiteListapiIdType.toUpperCase()} ID was found in the whitelist backup. API ID used to check: ${apiId}`
              );
            } else {
              deferrals.done(
                `Failed whitelist check: Not found in whitelist backup\n\nAPI ID used to check: ${apiId}`
              );
              DropPlayer(
                src,
                "You are not whitelisted: APIID was not found in the whitelist backup"
              );
              infoLog(
                `Denied ${name} (${apiId}) through whitelist, reason returned: Not found in whitelist backup`
              );
            }
          } else {
            deferrals.done(
              `Failed whitelist check: ${apiMsgToEnglish(
                whitelist.reason
              )} \n\nAPI ID used to check: ${apiId}`
            );
            DropPlayer(
              src,
              "You are not whitelisted: " + apiMsgToEnglish(whitelist.reason)
            );
            infoLog(
              `Denied ${name} (${apiId}) through whitelist, reason returned: ${apiMsgToEnglish(
                whitelist.reason
              )}`
            );
          }
        }
      );
    } catch (error) {
      let backupWhitelisted = checkBackup(apiId);
      if (backupWhitelisted) {
        deferrals.done();
        infoLog(
          `Successfully allowed ${name} (${apiId}) through whitelist, ${whiteListapiIdType.toUpperCase()} ID was found in the whitelist backup. API ID used to check: ${apiId}`
        );
      } else {
        deferrals.done(
          `Failed whitelist check: Not found in whitelist backup\n\nAPI ID used to check: ${apiId}`
        );
        DropPlayer(
          src,
          "You are not whitelisted: APIID was not found in the whitelist backup"
        );
        infoLog(
          `Denied ${name} (${apiId}) through whitelist, reason returned: Not found in whitelist backup`
        );
      }
    }
  });
  on("playerDropped", async (reason) => {
    const src = source;
    let accId = await findPlayerBySource(src);
    if (accId) {
      if (activePlayers.hasOwnProperty(accId)) {
        delete activePlayers[accId];
      }
    }
  });
  setInterval(() => {
    updateBackup();
  }, 1800000);

  setInterval(async () => {
    let allPlayers = exports.sonorancms.jsGetPlayers();
    // Saftey check in the event of backend outage to keep activePlayers up to date
    // activePlayers is used for role updates from CMS push events to ensure the player is still whitelisted
    if (allPlayers.length === 0) {
      activePlayers = {};
      return;
    }
    for (let player of allPlayers) {
      let test = await findPlayerBySource(player);
      if (!test) {
        let apiId;
        apiId = exports.sonorancms.getAppropriateIdentifier(
          player,
          whiteListapiIdType.toLowerCase()
        );
        if (!apiId)
          return errorLog(
            `Could not find the correct API ID to cross check with the whitelist... Requesting type: ${whiteListapiIdType.toUpperCase()}`
          );
        await addActivePlayer(apiId, player);
      }
    }
  }, 20 * 1000);
}

initialize();
