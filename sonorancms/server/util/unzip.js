const childProcess = require("child_process");
const path = require("path");
const fs = require("fs");

const moduleDirectories = ["ace-permissions", "clockin", "jobsync", "whitelist"];

function syncConfigFiles(debugMode) {
	moduleDirectories.forEach((moduleName) => {
		const configPath = path.join(GetResourcePath(GetCurrentResourceName()), "/server/modules/", moduleName, `${moduleName}_config.json`);
		const distConfigPath = path.join(GetResourcePath(GetCurrentResourceName()), "/server/modules/", moduleName, `${moduleName}_config.dist.json`);
		if (fs.existsSync(distConfigPath)) {
			if (!fs.existsSync(configPath)) {
				fs.renameSync(distConfigPath, configPath);
				console.log(`[${moduleName}] No existing config found. Renamed dist config to regular config.`);
			}
		} else if (debugMode) {
			console.log(`[${moduleName}] No dist config found. Skipping...`);
		}
	});
}

function createChildError(message) {
	return new Error(message || "Unzip worker failed without an error message.");
}

function getWorkerPath() {
	return path.join(GetResourcePath(GetCurrentResourceName()), "server", "util", "unzip-child.js");
}

function unzipUpdateInChild(file, dest) {
	return new Promise((resolve, reject) => {
		const worker = childProcess.fork(getWorkerPath(), [], {
			windowsHide: true,
			stdio: ["ignore", "pipe", "pipe", "ipc"],
		});

		let settled = false;

		const finish = (err) => {
			if (settled) return;
			settled = true;
			if (err) reject(err);
			else resolve();
		};

		if (worker.stdout) {
			worker.stdout.on("data", (chunk) => {
				const output = chunk.toString().trim();
				if (output.length > 0) console.log(output);
			});
		}

		if (worker.stderr) {
			worker.stderr.on("data", (chunk) => {
				const output = chunk.toString().trim();
				if (output.length > 0) console.error(output);
			});
		}

		worker.once("message", (message) => {
			if (message && message.ok) {
				finish();
				return;
			}
			finish(createChildError(message && message.error));
		});

		worker.once("error", (err) => finish(err));
		worker.once("exit", (code, signal) => {
			if (settled) return;
			if (code === 0) {
				finish();
				return;
			}

			const details = signal ? `signal ${signal}` : `code ${code}`;
			finish(createChildError(`Unzip worker exited with ${details}.`));
		});

		worker.send({ file, dest });
	});
}

exports("CheckConfigFiles", (debugMode) => {
	syncConfigFiles(debugMode);
});

exports("UnzipFile", (file, dest, debugMode) => {
	unzipUpdateInChild(file, dest)
		.then(() => {
			const globalChanges = [];
			syncConfigFiles(debugMode);
			exports[GetCurrentResourceName()].unzipCoreCompleted(true, globalChanges.length > 0 ? globalChanges : "nil");
		})
		.catch((err) => {
			exports[GetCurrentResourceName()].unzipCoreCompleted(false, err && err.message ? err.message : String(err));
		});
});

exports("makeDir", (dirPath) => {
	fs.mkdirSync(dirPath, { recursive: true });
});

exports("deleteDir", (dirPath) => {
	fs.rmdirSync(dirPath, { recursive: true });
});
