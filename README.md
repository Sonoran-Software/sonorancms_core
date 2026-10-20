# sonorancms_core
This resource is a core resource required by first party Sonoran CMS integrations for FiveM TM.

## Installation
[Click to view the installation guide](https://info.sonorancms.com/integration-capabilities/in-game-integration-resources/gta-rp-integrations/available-resources/core)

### Issues with garage script support? Check out our [documentation on this topic](https://info.sonorancms.com/integration-capabilities/qb-core-game-panel/using-the-game-panel/vehicles#supported-garage-scripts) or reach out to our [support team](https://support.sonoransoftware.com).

## Support diagnostics

When requested by support, run `sonorancms support <ticket ID>` in the server console. The ticket must have debug uploads enabled by support. Version 1.6.35 adds effective core and module configurations with credential fields redacted, dependency states/versions, player count, uptime, API state, and console/error/debug buffers. File status and truncation markers identify unavailable or oversized data; large logs keep recent output instead of failing the upload. Debug mode is left unchanged. Requires version 1.6.34 or newer.

## Manual updates

Starting with version 1.6.37, run `sonorancms update` in the **server console** to check for and install a newer official release. This command works even when `Config.allowAutoUpdate` is false, and it can be used on Windows or Linux. When installation finishes, the update helper restarts the resource immediately if `Config.restartWithPlayers` is true or the server is empty. Otherwise it waits for the server to become empty.

Servers on an older resource version must first install 1.6.37 or newer through the existing updater or the [release download](https://github.com/Sonoran-Software/sonorancms_core/releases); older versions do not have this console command. Automatic updates on Linux remain disabled.

Version 1.6.40 fixes a binary ZIP write bug in 1.6.37–1.6.39 that can cause
`Failed to extract core update. FILE_ENDED`. Those older updaters cannot install
the fix themselves: install the latest release manually while preserving your
configuration and whitelist backup, or change `writeResourceFile` in
`sonorancms/server/update.lua` to pass `#contents` instead of `-1`, restart the
resource, and then run `sonorancms update` again.

## Whitelist outage backup

With the whitelist module enabled, version 1.6.39 keeps its last successful CMS snapshot in
`sonorancms/server/modules/whitelist/whitelist_backup.json`. It refreshes on startup,
every five minutes, and after CMS account updates. The JSON contains the community,
server, API URL, identifier type, update time, enforcement state, and allowed IDs;
it contains no API key. Resource updates preserve this generated file.
Join-triggered refresh attempts share a 30-second cooldown to avoid rate limits.

Live whitelist denials take precedence. If CMS is unavailable or does not reply within
ten seconds, the saved snapshot allows known IDs, or everyone when CMS last confirmed
that both whitelist and blacklist rank lists were empty. A missing/corrupt/mismatched
backup denies entry with a clear message. Failed refreshes never replace the last good
snapshot, and an outage alone never kicks connected players.

Upgrade while CMS is available so the resource can create this scoped snapshot.
Old unscoped identifier arrays are not trusted, because earlier releases shipped a
sample backup indistinguishable from locally generated data. During an outage,
rank changes take effect once CMS is reachable again; the saved timestamp identifies
how old the fallback is.
