fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'psradio'
description 'Standalone public-safety radio: channels, codeplugs and its own voice transport (in development)'
version '0.2.0'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/radio.css',
    'web/css/models.css',
    'web/js/app.js',
    'web/js/ui/menu.js',
    'web/js/audio/codecs.js',
    'web/js/audio/capture.js',
    'web/js/audio/capture-worklet.js',
    'web/js/audio/playback.js',
    'web/js/audio/tones.js',
}

-- ox_lib provides the settings menu (/radiosetting) and must start first.
shared_scripts {
    '@ox_lib/init.lua',
    'shared/protocol.lua',
    'shared/util.lua',
}

-- config.lua is server-only on purpose: clients receive just the part of it
-- that their codeplug entitles them to see.
server_scripts {
    'config.lua',
    'server/ratelimit.lua',
    'server/settings.lua',
    'server/store.lua',
    'server/registry.lua',
    'server/framework.lua',
    'server/sessions.lua',
    'server/battery.lua',
    'server/voice.lua',
    'server/main.lua',
}

client_scripts {
    'client/anim.lua',
    'client/settings_menu.lua',
    'client/main.lua',
}

-- scully_emotemenu plays the transmit animations; without it the radio works
-- and nothing is animated.
dependencies {
    'ox_lib',
    'scully_emotemenu',
}
