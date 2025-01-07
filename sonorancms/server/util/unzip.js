const unzipper = require("@sonoransoftware/unzipper");
const deepMerge = require("deepmerge"); // for merging JSON objects
const path = require("path");
const fs = require("fs");

exports("CheckConfigFiles", (debugMode) => {
	const moduleDirectories = ["ace-permissions", "clockin", "jobsync", "whitelist"]; // Add all module directories here
	moduleDirectories.forEach((moduleName) => {
		const configPath = path.join(GetResourcePath(GetCurrentResourceName()), "/server/modules/", moduleName, `${moduleName}_config.json`);
		const distConfigPath = path.join(GetResourcePath(GetCurrentResourceName()), "/server/modules/", moduleName, `${moduleName}_config.dist.json`);
		if (fs.existsSync(distConfigPath)) {
			if (!fs.existsSync(configPath)) {
				// If the regular config doesn't exist, rename the dist config file to regular config file
				fs.renameSync(distConfigPath, configPath);
				console.log(`[${moduleName}] No existing config found. Renamed dist config to regular config.`);
			}
		} else {
			if (debugMode) {
				console.log(`[${moduleName}] No dist config found. Skipping...`);
			}
		}
	});
});

exports("UnzipFile", (file, dest, debugMode) => {
	try {
		fs.createReadStream(file).pipe(
			unzipper.Extract({ path: dest }).on("close", () => {
				// New logic to handle the JSON config update
				const moduleDirectories = ["ace-permissions", "clockin", "jobsync", "whitelist"]; // Add all module directories here
				let globalChanges = [];
				moduleDirectories.forEach((moduleName) => {
					const configPath = path.join(GetResourcePath(GetCurrentResourceName()), "/server/modules/", moduleName, `${moduleName}_config.json`);
					const distConfigPath = path.join(
						GetResourcePath(GetCurrentResourceName()),
						"/server/modules/",
						moduleName,
						`${moduleName}_config.dist.json`
					);
					if (fs.existsSync(distConfigPath)) {
						if (!fs.existsSync(configPath)) {
							// If the regular config doesn't exist, rename the dist config file to regular config file
							fs.renameSync(distConfigPath, configPath);
							console.log(`[${moduleName}] No existing config found. Renamed dist config to regular config.`);
						}
					} else {
						if (debugMode) {
							console.log(`[${moduleName}] No dist config found. Skipping...`);
						}
					}
				});
				exports[GetCurrentResourceName()].unzipCoreCompleted(true, globalChanges.length > 0 ? globalChanges : "nil");
			})
		);
	} catch (ex) {
		exports[GetCurrentResourceName()].unzipCoreCompleted(false, ex?.message);
	}
});

exports("makeDir", (path) => {
	fs.mkdirSync(path, { recursive: true });
});
