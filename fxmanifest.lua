fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'psradio'
description 'Standalone public-safety radio: channels, codeplugs and its own voice transport (in development)'
version '0.1.0'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/radio.css',
    'web/js/app.js',
    'web/js/audio/codecs.js',
    'web/js/audio/capture.js',
    'web/js/audio/capture-worklet.js',
    'web/js/audio/playback.js',
    'web/js/audio/tones.js',
}

shared_scripts {
    'shared/protocol.lua',
    'shared/util.lua',
}

-- config.lua is server-only on purpose: clients receive just the part of it
-- that their codeplug entitles them to see.
server_scripts {
    'config.lua',
    'server/ratelimit.lua',
    'server/store.lua',
    'server/registry.lua',
    'server/framework.lua',
    'server/sessions.lua',
    'server/voice.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}
