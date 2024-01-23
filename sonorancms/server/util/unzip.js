const unzipper = require("unzipper");
const deepMerge = require('deepmerge'); // for merging JSON objects
const path = require('path');
const fs = require('fs');

function rmdirRecursive(dirPath) {
	if (fs.existsSync(dirPath)) {
		fs.readdirSync(dirPath).forEach((file) => {
			const curPath = path.join(dirPath, file);
			if (fs.lstatSync(curPath).isDirectory()) {
				rmdirRecursive(curPath);
			} else {
				fs.unlinkSync(curPath);
			}
		});
		fs.rmdirSync(dirPath);
	}
}

function moveFiles(source, destination) {
	// Get a list of all files and directories in the source directory
	const files = fs.readdirSync(source);

	// Loop through each file or directory
	files.forEach((file) => {
		const sourcePath = path.join(source, file);
		const destPath = path.join(destination, file);

		// If it's a directory, recursively move its contents
		if (fs.statSync(sourcePath).isDirectory()) {
			moveFiles(sourcePath, destPath);
		} else {
			// Otherwise, it's a file - move it to the destination directory
			fs.copyFileSync(sourcePath, destPath);
		}
	});
}

function findChanges(existingConfig, defaultConfig, basePath = '') {
	let changes = [];

	function arraysEqual(arr1, arr2) {
		if (arr1.length !== arr2.length) return false;
		for (let i = 0; i < arr1.length; i++) {
			if (arr1[i] !== arr2[i]) return false;
		}
		return true;
	}

	function compareValues(key, value1, value2, path) {
		const fullPath = path ? `${path}.${key}` : key;
		if (Array.isArray(value1) && Array.isArray(value2)) {
			if (!arraysEqual(value1, value2)) {
				changes.push(`${fullPath} was changed from ${JSON.stringify(value2)} to ${JSON.stringify(value1)}`);
			}
		} else if (typeof value1 === 'object' && typeof value2 === 'object') {
			const childChanges = findChanges(value1, value2, fullPath);
			changes = changes.concat(childChanges);
		} else {
			if (value1 !== value2) {
				changes.push(`${fullPath} was changed from ${JSON.stringify(value2)} to ${JSON.stringify(value1)}`);
			}
		}
	}

	// Check for any properties that are in the existing config but not in the default config
	Object.keys(existingConfig).forEach(key => {
		if (!(key in defaultConfig)) {
			changes.push(`${basePath}${key} is no longer used and will be removed.`);
			delete existingConfig[key]; // Remove the key from the existing config
		} else {
			compareValues(key, existingConfig[key], defaultConfig[key], basePath);
		}
	});
	return changes;
}


exports('UnzipFile', (file, dest, type) => {
	if (type === "core") {
		try {
			fs.createReadStream(file).pipe(unzipper.Extract({ path: dest }).on('close', () => {
				// New logic to handle the JSON config update
				const moduleDirectories = ['ace-permissions', 'clockin', 'jobsync', 'whitelist']; // Add all module directories here
				let globalChanges = [];
				moduleDirectories.forEach(moduleName => {
					const configPath = path.join(dest, moduleName, `${moduleName}_config.json`);
					const distConfigPath = path.join(dest, moduleName, `${moduleName}_config.dist.json`);

					if (fs.existsSync(distConfigPath)) {
						if (!fs.existsSync(configPath)) {
							// If the regular config doesn't exist, rename the dist config file to regular config file
							fs.renameSync(distConfigPath, configPath);
							console.log(`[${moduleName}] No existing config found. Renamed dist config to regular config.`);
						} else {
							// If the regular config exists, proceed with the merge
							let existingConfig = JSON.parse(fs.readFileSync(configPath));
							const distConfig = JSON.parse(fs.readFileSync(distConfigPath));
							const mergedConfig = deepMerge(existingConfig, distConfig);
							const changesArray = findChanges(existingConfig, distConfig);
							if (changesArray.length > 0) {
								fs.writeFileSync(configPath, JSON.stringify(mergedConfig, null, 2));
								console.log(`[${moduleName}] Config updated with changes:`, changesArray);
								globalChanges = globalChanges.concat(changesArray.map(change => `[${moduleName}] ${change}`));
							}
						}
					}
				});
				exports[GetCurrentResourceName()].unzipCoreCompleted(true, globalChanges.length > 0 ? globalChanges : 'nil');
			}));
		} catch (ex) {
			exports[GetCurrentResourceName()].unzipCoreCompleted(false, ex);
		}
	} else {
		try {
			let tempFolder = GetResourcePath(GetCurrentResourceName()) + '/addonupdates/' + type
			if (fs.existsSync(tempFolder)) { rmdirRecursive(tempFolder) }
			fs.mkdirSync(tempFolder)
			fs.createReadStream(file).pipe(unzipper.Extract({ path: tempFolder }).on('close', () => {
				const folder = fs.readdirSync(tempFolder);
				if (folder[0].includes('-latest')) {
					moveFiles(tempFolder + '/' + folder, dest)
					rmdirRecursive(tempFolder);
					exports[GetCurrentResourceName()].unzipAddonCompleted(true, 'nil', type);
				}
			}))
		} catch (ex) {
			exports[GetCurrentResourceName()].unzipAddonCompleted(false, ex, type);
		}
	}
});

exports('makeDir', (path) => {
	fs.mkdirSync(path, { recursive: true })
})