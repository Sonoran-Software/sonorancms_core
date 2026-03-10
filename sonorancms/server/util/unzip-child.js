(() => {
	const unzipper = require("@sonoransoftware/unzipper");
	const fs = require("fs");

	function unzipUpdate(file, dest) {
		return new Promise((resolve, reject) => {
			fs.createReadStream(file)
				.pipe(unzipper.Extract({ path: dest }))
				.on("close", resolve)
				.on("error", reject);
		});
	}

	function sendResult(message, exitCode) {
		if (typeof process.send === "function") {
			process.send(message, () => process.exit(exitCode));
			return;
		}

		process.exit(exitCode);
	}

	process.once("message", ({ file, dest }) => {
		unzipUpdate(file, dest)
			.then(() => sendResult({ ok: true }, 0))
			.catch((err) => sendResult({ ok: false, error: err && err.message ? err.message : String(err) }, 1));
	});
})();
