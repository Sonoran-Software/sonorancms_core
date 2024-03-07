/**
 * Gets the current CPU usage percentage
 * @returns {number} CPU usage percentage
 */
function getCPUUsage() {
	const cpus = os.cpus();
	let totalIdle = 0;
	let totalTick = 0;
	cpus.forEach((cpu) => {
		for (const type in cpu.times) {
			totalTick += cpu.times[type];
		}
		totalIdle += cpu.times.idle;
	});
	return ((totalTick - totalIdle) / totalTick) * 100;
}

/**
 * Gets the current RAM usage percentage
 * @returns {number} RAM usage percentage
 */
function getRAMUsage() {
	const totalRAM = os.totalmem();
	const freeRAM = os.freemem();
	return ((totalRAM - freeRAM) / totalRAM) * 100;
}

/**
 * Gets the current CPU usage in raw ticks
 * @returns {number} CPU usage in raw ticks
 */
function getCPURaw() {
	const cpus = os.cpus();
	let totalIdle = 0;
	let totalTick = 0;
	cpus.forEach((cpu) => {
		for (const type in cpu.times) {
			totalTick += cpu.times[type];
		}
		totalIdle += cpu.times.idle;
	});
	return totalTick - totalIdle;
}

/**
 * Gets the current RAM usage in raw bytes
 * @returns {number} RAM usage in raw bytes
 */
function getRAMRaw() {
	const totalRAM = os.totalmem();
	const freeRAM = os.freemem();
	return totalRAM - freeRAM;
}

/**
 * Gets the current system information
 * @returns {object} System information
 */
exports("getSystemInfo", () => {
	return { cpuUsage: getCPUUsage(), ramUsage: getRAMUsage(), cpuRaw: getCPURaw(), ramRaw: getRAMRaw() };
});

/**
 *
 * @param {playerSource} source
 * @param {string} type
 * @returns {string}
 */
const getAppropriateIdentifier = (source, type) => {
	const identifiers = getPlayerIdentifiers(source);
	let properIdentifiers = {
		discord: "",
		steam: "",
		license: "",
	};
	identifiers.forEach((identifier) => {
		const splitIdentifier = identifier.split(":");
		const identType = splitIdentifier[0];
		const identId = splitIdentifier[1];
		switch (identType) {
			case "discord":
				properIdentifiers.discord = identId;
				break;
			case "steam":
				properIdentifiers.steam = identId;
				break;
			case "license":
				properIdentifiers.license = identId;
				break;
		}
	});
	const cleanType = type.replace(/^'(.*)'$/, "$1");
	if (properIdentifiers[cleanType] === "") {
		errorLog(`No ${cleanType} identifier found for ${GetPlayerName(source)}...`);
		return "NOT FOUND";
	} else {
		return properIdentifiers[cleanType];
	}
};

/**
 *
 * @param {int} ms
 * @returns {Promise}
 */
const sleep = (ms) => {
	return new Promise((resolve) => setTimeout(resolve, ms));
};

module.exports = {
	getAppropriateIdentifier,
	sleep,
};