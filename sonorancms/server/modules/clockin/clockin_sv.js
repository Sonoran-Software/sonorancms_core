const utils = require('./clockin_utills');
const luaConfig = LoadResourceFile(GetCurrentResourceName(), "/config.lua");
const cleanLuaConfig = luaConfig.replace(/--.*/g, '');
const serverConfig = {};
const config = require('./clockin_config.json');
cleanLuaConfig.replace(/Config\.(\w+)\s*=\s*(.*?)(?=\n|$)/g, (match, key, value) => {
    serverConfig[key] = value.trim();
});
let apiIdType = serverConfig.apiIdType;

async function initialize() {
		await utils.sleep(2000)
		if (config) {
			global.exports('clockPlayerIn', async (source, forceClockIn = false) => {
				const apiId = utils.getAppropriateIdentifier(source, apiIdType);
				await clockPlayerIn(apiId, forceClockIn).then((inOrOut) => {
					return { success: true, in: inOrOut };
				}).catch((err) => {
					return { success: false, err };
				});
			});
			if (config.enableCommand) {
				RegisterCommand(config.command || 'clockin', async (source) => {
					const apiId = utils.getAppropriateIdentifier(source, apiIdType);
					await clockPlayerIn(apiId, false).then((inOrOut) => {
						if (inOrOut == false) {
							emitNet('chat:addMessage', source, {
								color: [255, 0, 0],
								multiline: false,
								args: [`^3^*Sonoran CMS:^7 Successfully clocked in!`]
							});
						} else if (inOrOut == true) {
							emitNet('chat:addMessage', source, {
								color: [255, 0, 0],
								multiline: false,
								args: [`^3^*Sonoran CMS:^7 Successfully clocked out!`]
							});
						} else {
							emitNet('chat:addMessage', source, {
								color: [255, 0, 0],
								multiline: false,
								args: [`^8^*Sonoran CMS:^7 You do not have permissions to use this command...`]
							});
							utils.errorLog(`${GetPlayerName(source)} (${apiId}) did not have perms to clock in...`);
						}
					}).catch((err) => {
						emitNet('chat:addMessage', source, {
							color: [255, 0, 0],
							multiline: false,
							args: [`^8^*Sonoran CMS:^7 ${err || 'An error occured while clocking in...'}`]
						});
						utils.errorLog(`An error occured while clocking in ${GetPlayerName(source)} (${apiId})... ${err}`);
					});
				}, config.useAcePermissions);
				onNet('SonoranCMS::ClockIn::Server::ClockPlayerIn', async (forceClockIn) => {
					const src = global.source;
					const apiId = utils.getAppropriateIdentifier(src, apiIdType);
					await clockPlayerIn(apiId, forceClockIn).then((inOrOut) => {
						utils.infoLog(`Clocked player ${GetPlayerName(src)} (${apiId}) ${inOrOut ? 'out' : 'in'}!`);
					}).catch((err) => {
						utils.errorLog(`Failed to clock player ${GetPlayerName(src)} (${apiId}) ${inOrOut ? 'out' : 'in'}...`);
					});
				});
			}
		} else {
			utils.errorLog('No config found... looked for config.json & server convars...');
		}
}

initialize();