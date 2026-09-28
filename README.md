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
