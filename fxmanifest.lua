fx_version 'cerulean'
game 'gta5'

name "qbx_garages"
author "SwisserAI"
description "Generated with SwisserAI - https://ai.swisser.dev | Custom all-access Qbox garage system"
repository "https://github.com/Qbox-project/qbx_garages"
version "1.2.1"

ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'shared/*',
}

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/default-calculate-impound-fee.lua',
    'server/main.lua',
    'server/spawn-vehicle.lua',
}

ui_page "html/ui.html"

files {
    "config/client.lua",
    "locales/*.json",
    "html/ui.html",
    "html/style.css",
    "html/script.js",
    "html/tailwind.css",
    "html/fonts/*.woff2",
    "html/fonts.css"
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'