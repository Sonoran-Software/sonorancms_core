fx_version 'cerulean'
games {'gta5'}

author 'Sonoran Software Systems'
real_name 'Sonoran CMS FiveM Integration'
description 'Sonoran CMS to FiveM translation layer'
version '1.3.3'
lua54 'yes'

server_scripts {'server/*.lua', 'config.lua', 'server/util/unzip.js', 'server/util/http.js', 'server/util/sonoran.js', 'server/util/utils.js', '@oxmysql/lib/MySQL.lua', 'server/util/imageHandler.js'}
client_scripts {'client/*.lua'}
ui_page 'nui/index.html'
dependency '/assetpacks'
