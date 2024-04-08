fx_version 'cerulean'
games {'gta5'}

author 'Sonoran Software Systems'
real_name 'Sonoran CMS FiveM Integration'
description 'Sonoran CMS to FiveM translation layer'
version '1.5.2'
lua54 'yes'

server_scripts {'server/*.lua', 'config.lua', 'server/util/unzip.js', 'server/util/http.js', 'server/util/sonoran.js', 'server/util/utils.js', '@oxmysql/lib/MySQL.lua', 'server/util/imageHandler.js', 'server/modules/**/*_sv.js', 'server/modules/**/*_sv.lua'}
client_scripts {'client/*.lua', 'server/modules/**/*_cl.js', 'server/modules/**/*_cl.lua'}
ui_page 'nui/index.html'
dependency '/assetpacks'
