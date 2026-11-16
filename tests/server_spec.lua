-- Server behaviour tests. Run with: cd tests && npm test
local Ev = PSR.Event
local Registry, Store, Sessions, Voice, Framework = PSR.Registry, PSR.Store, PSR.Sessions, PSR.Voice, PSR.Framework

local passed, failed = 0, 0
__failed = 0

local function check(cond, what)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        __failed = failed
        print('  FAIL: ' .. what)
    end
end

local function section(name) print('- ' .. name) end

local PAYLOAD = 'AAECAwQFBgc='   -- valid base64

local function connect(src, license, aces)
    T.identifiers[src] = license
    T.aces[src] = {}
    for _, a in ipairs(aces or {}) do T.aces[src][a] = true end
    T.fire(Ev.svReady, src, PSR.PROTOCOL_VERSION, { opus = true })
    local init = T.take(Ev.clInit, src)
    return init[1] and init[1][1]
end

local function powerOn(src, channel)
    T.fire(Ev.svPower, src, true)
    if channel then T.fire(Ev.svSelect, src, channel) end
    T.clear()
end

-- Starts a transmission and returns its id (or nil and the denial reason).
local function key(src, seq)
    T.fire(Ev.svTxStart, src, seq or 1)
    local granted = T.take(Ev.clTxGranted, src)
    if granted[1] then return granted[1][2], granted[1][3] end
    local denied = T.take(Ev.clTxDenied, src)
    return nil, denied[1] and denied[1][2]
end

-- ---------------------------------------------------------------------------
section('config validation')
check(#Registry.zones == 3, 'demo config has 3 zones')
do
    local n = 0
    for _ in pairs(Registry.channels) do n = n + 1 end
    check(n == 12, 'demo config has 12 channels')
end
check(Registry.codeplugs.leo ~= nil and Registry.codeplugs.fire ~= nil, 'demo codeplugs exist')
check(Registry.codeplugForJob('police', 0) == 'leo', 'police grade 0 -> leo')
check(Registry.codeplugForJob('police', 4) == 'leo_command', 'police grade 4 -> leo_command')
check(Registry.codeplugForJob('police', 9) == 'leo_command', 'police grade 9 -> leo_command')
check(Registry.codeplugForJob('ambulance', 2) == 'fire', 'short-form job mapping')
check(Registry.codeplugForJob('mechanic', 3) == nil, 'unmapped job gets nothing')

do
    local saved = { zones = Registry.zones, channels = Registry.channels, codeplugs = Registry.codeplugs,
        order = Registry.codeplugOrder, jobs = Registry.jobs, voice = Registry.voice }
    local warnings = Registry.build({
        voice = { opusBitrate = 9999999, framesPerPacket = 0, defaultCodec = 'nope' },
        zones = {
            { id = 'ok', name = 'OK', channels = {
                { id = 'a', name = 'A' },
                { id = 'a', name = 'DUP' },
                { id = 'bad id!', name = 'X' },
                { id = 't', name = 'T', type = 'trunked' },
                { id = 'm', name = 'M', mode = 'fm' },
                { id = 'c', name = 'C', codec = 'imbe' },
                { id = 'long', name = 'THIS NAME IS FAR TOO LONG' },
            } },
            { id = 'ok', name = 'DUPZONE', channels = {} },
            'not a table',
        },
        codeplugs = { p = { tx = { 'a', 'ghost' } }, ['bad id'] = {} },
        jobs = { cop = 'p', nobody = 'missing', ranked = { ranks = { [2] = 'p', [3] = 'missing' } } },
    })
    local n = 0
    for _ in pairs(Registry.channels) do n = n + 1 end
    check(n == 1, 'only the valid channel survives (got ' .. n .. ')')
    check(#Registry.zones == 1, 'duplicate and malformed zones dropped')
    check(Registry.codeplugs.p and Registry.codeplugs.p.tx.a and not Registry.codeplugs.p.tx.ghost, 'unknown channel removed from codeplug')
    check(Registry.codeplugs['bad id'] == nil, 'invalid codeplug id dropped')
    check(Registry.jobs.cop ~= nil and Registry.jobs.nobody == nil, 'job pointing at missing codeplug dropped')
    check(Registry.codeplugForJob('ranked', 1) == nil and Registry.codeplugForJob('ranked', 2) == 'p', 'rank-only job mapping')
    check(Registry.voice.opusBitrate == 64000 and Registry.voice.framesPerPacket == 1 and Registry.voice.defaultCodec == 'opus',
        'voice settings clamped')
    check(#warnings >= 9, 'each problem produced a warning (got ' .. #warnings .. ')')
    Registry.zones, Registry.channels, Registry.codeplugs = saved.zones, saved.channels, saved.codeplugs
    Registry.codeplugOrder, Registry.jobs, Registry.voice = saved.order, saved.jobs, saved.voice
end

-- ---------------------------------------------------------------------------
section('access')
do
    local init = connect(1, 'license:aaa')
    check(init ~= nil and init.access == false, 'unmapped player gets no access view')
    T.fire(Ev.svPower, 1, true)
    check(#T.take(Ev.clState, 1) == 0, 'unmapped player cannot power on')
    check(T.take(Ev.clNotify, 1)[1][1] == 'no_access', 'unmapped player is told why')
end

do
    local init = connect(2, 'license:bbb', { 'psradio.codeplug.fire' })
    check(init.access and init.access.codeplug.id == 'fire', 'ACE grants the fire codeplug')
    local seen, txCount = 0, 0
    for _, z in ipairs(init.access.zones) do
        for _, c in ipairs(z.channels) do
            seen = seen + 1
            if c.tx then txCount = txCount + 1 end
        end
    end
    check(seen == 6 and txCount == 4, 'view holds only permitted channels (4 tx + 2 scan), got ' .. seen .. '/' .. txCount)
    check(init.strings.tx_busy ~= nil, 'locale strings are sent')
    check(init.state.unitId ~= nil and init.state.power == false, 'radio starts powered off with a unit id')
end

do  -- framework job mapping through a fake ESX
    T.resources.es_extended = 'started'
    local jobs = { [3] = { name = 'police', grade = 1 }, [4] = { name = 'police', grade = 5 }, [5] = { name = 'mechanic', grade = 9 } }
    T.exportsOf.es_extended = {
        getSharedObject = function()
            return { GetPlayerFromId = function(src) return jobs[src] and { job = jobs[src] } or nil end }
        end,
    }
    check(Framework.detect('auto') == 'es_extended', 'ESX is auto-detected')
    check(connect(3, 'license:ccc').access.codeplug.id == 'leo', 'police grade 1 -> leo')
    check(connect(4, 'license:ddd').access.codeplug.id == 'leo_command', 'police grade 5 -> leo_command')
    check(connect(5, 'license:eee').access == false, 'mechanic gets no radio')

    -- job change is picked up by the access poll
    jobs[5] = { name = 'ambulance', grade = 0 }
    T.clear()
    T.advance(5100)
    local access = T.take(Ev.clAccess, 5)
    check(access[1] and access[1][1] and access[1][1].codeplug.id == 'fire', 'job change grants a codeplug within the poll interval')
    check(#T.take(Ev.clAccess, 3) == 0, 'unchanged players are not re-sent their access')
end

-- ---------------------------------------------------------------------------
section('channel selection and persistence')
do
    T.fire(Ev.svPower, 3, true)
    check(T.take(Ev.clState, 3)[1][1].power == true, 'power on is confirmed')
    T.fire(Ev.svSelect, 3, 'city-fire')
    check(T.take(Ev.clNotify, 3)[1][1] == 'scan_only', 'scan-only channel is refused for selection')
    T.fire(Ev.svSelect, 3, 'nope')
    check(T.take(Ev.clNotify, 3)[1][1] == 'invalid_channel', 'unknown channel is refused')
    T.fire(Ev.svSelect, 3, { 'table' })
    T.fire(Ev.svSelect, 3, 'bad id!')
    check(#T.take(Ev.clState, 3) == 0, 'malformed channel ids are ignored')
    T.fire(Ev.svSelect, 3, 'city-disp')
    check(T.take(Ev.clState, 3)[1][1].channelId == 'city-disp', 'valid channel is selected')
    check(T.ownExports.getPlayerChannel(3) == 'city-disp', 'export reports the channel')

    -- fire codeplug cannot tune a law-enforcement channel
    T.fire(Ev.svPower, 2, true)
    T.fire(Ev.svSelect, 2, 'city-c2c')
    T.clear()
    check(T.ownExports.getPlayerChannel(2) == nil, 'channel outside the codeplug is refused')

    -- reconnect restores the last channel
    T.fire('playerDropped', 3)
    check(Sessions.get(3) == nil, 'session removed on disconnect')
    local init = connect(3, 'license:ccc')
    check(init.state.channelId == 'city-disp' and init.state.power == false, 'last channel restored, radio off')
end

-- ---------------------------------------------------------------------------
section('transmission')
do
    powerOn(3, 'city-disp')
    powerOn(4, 'city-disp')
    connect(6, 'license:fff', { 'psradio.codeplug.leo' })
    powerOn(6, 'city-c2c')

    local txId, params = key(3, 7)
    check(txId ~= nil, 'talker is granted')
    check(params and params.codec == PSR.Codec.opus and params.framesPerPacket == 3, 'grant carries codec parameters')
    local start = T.take(Ev.clRxStart, 4)
    check(#start == 1 and start[1][2] == txId and start[1][1] == 'city-disp', 'listener on the channel gets rxStart')
    check(not tostring(start[1][3]):find('license'), 'label does not leak an identifier')
    check(#T.take(Ev.clRxStart, 6) == 0, 'player on another channel gets nothing')
    check(T.ownExports.isTransmitting(3) == true, 'export reports transmitting')

    T.fire(Ev.svTxFrame, 3, txId, 0, PAYLOAD)
    check(#T.take(Ev.clRxFrame, 4) == 1, 'frame relayed to the listener')
    check(#T.take(Ev.clRxFrame, 3) == 0, 'frame not echoed to the talker')
    check(#T.take(Ev.clRxFrame, 6) == 0, 'frame not sent to other channels')

    T.fire(Ev.svTxFrame, 3, txId, 0, PAYLOAD)
    check(#T.take(Ev.clRxFrame) == 0, 'replayed sequence number dropped')
    T.fire(Ev.svTxFrame, 3, txId, 500, PAYLOAD)
    check(#T.take(Ev.clRxFrame) == 0, 'implausible sequence jump dropped')
    T.fire(Ev.svTxFrame, 3, txId + 1, 1, PAYLOAD)
    check(#T.take(Ev.clRxFrame) == 0, 'wrong transmission id dropped')
    T.fire(Ev.svTxFrame, 4, txId, 1, PAYLOAD)
    check(#T.take(Ev.clRxFrame) == 0, 'a listener cannot inject into another player\'s transmission')
    T.fire(Ev.svTxFrame, 3, txId, 1, '<script>')
    T.fire(Ev.svTxFrame, 3, txId, 1, 12345)
    T.fire(Ev.svTxFrame, 3, txId, 1, string.rep('A', 8192))
    T.fire(Ev.svTxFrame, 3, txId, 1.5, PAYLOAD)
    T.fire(Ev.svTxFrame, 3, txId, 'x', PAYLOAD)
    check(#T.take(Ev.clRxFrame) == 0, 'malformed payloads and sequence numbers dropped')
    T.fire(Ev.svTxFrame, 3, txId, 1, PAYLOAD)
    check(#T.take(Ev.clRxFrame, 4) == 1, 'valid frame still accepted afterwards')

    local _, reason = key(4, 1)
    check(reason == 'tx_busy', 'second talker is refused while the channel is busy')

    -- late joiner gets the stream header
    T.fire(Ev.svSelect, 6, 'city-disp')
    check(#T.take(Ev.clRxStart, 6) == 1, 'late joiner receives rxStart')

    T.fire(Ev.svTxStop, 3)
    local stop = T.take(Ev.clRxStop, 4)
    check(#stop == 1 and stop[1][3] == 'released', 'listeners are told the transmission ended')
    check(#T.take(Ev.clTxEnded, 3) == 0, 'talker is not notified of their own release')
    T.fire(Ev.svTxFrame, 3, txId, 2, PAYLOAD)
    check(#T.take(Ev.clRxFrame) == 0, 'frames after release are dropped')
    check(key(4, 2) ~= nil, 'channel is free again')
    T.fire(Ev.svTxStop, 4)
    T.clear()
end

do  -- preconditions
    T.fire(Ev.svPower, 6, false)
    local _, reason = key(6, 1)
    check(reason == 'radio_off', 'cannot transmit with the radio off')
    connect(7, 'license:ggg', { 'psradio.codeplug.leo' })
    T.fire(Ev.svPower, 7, true)
    T.clear()
    _, reason = key(7, 1)
    check(reason == 'no_channel', 'cannot transmit without a channel')
    T.fire(Ev.svTxStart, 7, 'x')
    T.fire(Ev.svTxStart, 7, -1)
    check(#T.take(Ev.clTxGranted) + #T.take(Ev.clTxDenied) == 0, 'malformed txStart ignored')
end

do  -- codec fallback for a client without Opus
    T.identifiers[8] = 'license:hhh'
    T.aces[8] = { ['psradio.codeplug.leo'] = true }
    T.fire(Ev.svReady, 8, PSR.PROTOCOL_VERSION, { opus = false })
    powerOn(8, 'county-disp')
    local txId, params = key(8, 1)
    check(txId and params.codec == PSR.Codec.adpcm, 'client without Opus is granted ADPCM')
    T.fire(Ev.svTxStop, 8)
    T.fire(Ev.svReady, 9, 999, {})
    check(#T.take(Ev.clInit, 9) == 0, 'wrong protocol version is not initialised')
    T.clear()
end

-- ---------------------------------------------------------------------------
section('limits')
do
    T.advance(3000)
    T.clear()
    local txId = key(3, 20)
    local accepted = 0
    for seq = 0, 199 do
        T.fire(Ev.svTxFrame, 3, txId, seq, PAYLOAD)
    end
    accepted = #T.take(Ev.clRxFrame, 4)
    check(accepted > 0 and accepted < 60, 'voice packet flood is rate limited (relayed ' .. accepted .. ' of 200)')
    T.fire(Ev.svTxStop, 3)
    T.clear()

    -- PTT spam
    T.advance(5000)
    local grants = 0
    for i = 1, 20 do
        if key(3, 100 + i) then grants = grants + 1 end
        T.fire(Ev.svTxStop, 3)
    end
    check(grants >= 1 and grants <= 5, 'PTT spam is rate limited (granted ' .. grants .. ' of 20)')
    T.advance(5000)
    T.clear()

    -- time-out
    local txId2 = key(4, 50)
    check(txId2 ~= nil, 'transmission for time-out test granted')
    local seq = 0
    for _ = 1, 59 do
        T.advance(1000)
        T.fire(Ev.svTxFrame, 4, txId2, seq, PAYLOAD)
        seq = seq + 1
    end
    check(Voice.bySrc[4] ~= nil, 'transmission still alive just under the time-out')
    T.advance(1500)
    local ended = T.take(Ev.clTxEnded, 4)
    check(#ended == 1 and ended[1][2] == 'tx_timeout', 'transmission is ended at the time-out')
    check(Voice.active['city-disp'] == nil, 'channel freed after time-out')
    T.clear()

    -- stall
    T.advance(5000)
    check(key(4, 51) ~= nil, 'transmission for stall test granted')
    T.advance(3500)
    ended = T.take(Ev.clTxEnded, 4)
    check(#ended == 1 and ended[1][2] == 'tx_stalled', 'silent transmission is ended')
    T.clear()

    -- control flood
    T.advance(5000)
    for _ = 1, 200 do T.fire(Ev.svPower, 4, true) end
    local n = #T.take(Ev.clState, 4)
    check(n > 0 and n <= 31, 'control messages are rate limited (answered ' .. n .. ' of 200)')
    T.advance(5000)
    T.clear()
end

-- ---------------------------------------------------------------------------
section('disconnect, access loss and shutdown')
do
    local txId = key(3, 200)
    check(txId ~= nil, 'granted before disconnect')
    T.clear()
    T.fire('playerDropped', 3)
    local stop = T.take(Ev.clRxStop, 4)
    check(#stop == 1 and stop[1][3] == 'disconnect', 'listeners are told when the talker disconnects')
    check(Voice.active['city-disp'] == nil and Voice.bySrc[3] == nil, 'no transmission left behind')
    check(Sessions.members['city-disp'] and Sessions.members['city-disp'][3] == nil, 'membership cleaned up')

    -- access revoked mid-transmission
    T.advance(5000)
    check(key(6, 300) == nil, 'radio 6 is off')
    powerOn(6, 'city-disp')
    check(key(6, 301) ~= nil, 'radio 6 transmitting')
    T.aces[6] = {}
    T.clear()
    T.advance(5100)
    check(Voice.bySrc[6] == nil, 'transmission stops when access is revoked')
    local access = T.take(Ev.clAccess, 6)
    check(#access == 1 and access[1][1] == false, 'client is told access is gone')
    check(Sessions.get(6).power == false and Sessions.get(6).channelId == nil, 'radio is switched off and detuned')

    -- shutdown
    T.advance(5000)
    check(key(4, 400) ~= nil, 'granted before shutdown')
    T.files['data/state.json'] = nil
    T.commands.callsign(4, { 'UNSAVED' })      -- a change the periodic save has not written yet
    T.fire('onResourceStop', nil, 'some-other-resource')
    check(Voice.bySrc[4] ~= nil, 'another resource stopping changes nothing')
    T.fire('onResourceStop', nil, 'psradio')
    check(Voice.bySrc[4] == nil, 'transmissions end on resource stop')
    check(T.files['data/state.json'] ~= nil and T.files['data/state.json']:find('UNSAVED', 1, true) ~= nil,
        'unsaved changes are written on resource stop')
end

-- ---------------------------------------------------------------------------
section('callsigns')
do
    T.advance(5000)
    T.clear()
    T.commands.callsign(4, { '2L-319' })
    check(T.take(Ev.clNotify, 4)[1][1] == 'callsign_set', 'valid callsign accepted')
    check(Sessions.label(Sessions.get(4)) == '2L-319', 'callsign becomes the radio label')
    T.commands.callsign(4, { '<b>x</b>' })
    check(T.take(Ev.clNotify, 4)[1][1] == 'callsign_invalid', 'markup rejected')
    T.commands.callsign(4, { 'WAYTOOLONGCALLSIGN' })
    check(T.take(Ev.clNotify, 4)[1][1] == 'callsign_invalid', 'over-long callsign rejected')
    T.commands.callsign(4, { 'two', 'words' })
    check(T.take(Ev.clNotify, 4)[1][1] == 'callsign_invalid', 'multiple words rejected')
    check(Sessions.get(4).record.callsign == '2L-319', 'rejected input leaves the callsign unchanged')
    T.commands.callsign(4, { 'clear' })
    check(Sessions.get(4).record.callsign == nil, 'callsign cleared')
    T.commands.callsign(0, { 'console' })
    T.commands.callsign(99, { 'ghost' })
    check(true, 'console and unknown sources do not error')
    T.clear()
end

-- ---------------------------------------------------------------------------
section('persistence')
do
    T.commands.callsign(4, { 'K9-1' })
    check(Store.save() == true, 'dirty state is written')
    check(Store.save() == false, 'clean state is not rewritten')
    local saved = json.decode(T.files['data/state.json'])
    check(saved.version == 1 and saved.players['license:ddd'].callsign == 'K9-1', 'file holds the callsign under version 1')
    check(saved.players['license:ccc'].lastChannel == 'city-disp', 'file holds the last channel')

    check(Store.load() == 'loaded', 'state reloads')
    check(Store.player('license:ddd').callsign == 'K9-1', 'callsign survives a reload')
    local id = Store.player('license:new').unitId
    check(Store.player('license:new').unitId == id, 'unit id is stable per player')
    check(Store.player(nil).unitId ~= Store.player(nil).unitId, 'players without an identifier get throwaway ids')

    T.files['data/state.json'] = '{ this is not json'
    check(Store.load() == 'corrupt', 'corrupt file detected')
    check(T.files['data/state.corrupt.json'] == '{ this is not json', 'corrupt file is kept as a backup')
    check(Store.state.version == 1 and next(Store.state.players) == nil, 'store starts fresh after corruption')

    T.files['data/state.json'] = '{"version":99,"players":{}}'
    check(Store.load() == 'newer' and Store.readOnly, 'file from a newer version makes the store read-only')
    Store.touch()
    check(Store.save() == false and T.files['data/state.json'] == '{"version":99,"players":{}}', 'newer file is never overwritten')

    -- migration path, exercised with a pretend version 0
    Store.migrations[0] = function(old)
        return { nextUnitId = 5, players = { ['license:zzz'] = { unitId = 4, callsign = old.cs } }, patches = {} }
    end
    T.files['data/state.json'] = '{"version":0,"cs":"OLD-1"}'
    check(Store.load() == 'migrated', 'older file is migrated')
    check(Store.state.version == 1 and Store.state.players['license:zzz'].callsign == 'OLD-1', 'migration result is used')
    check(Store.save() == true and json.decode(T.files['data/state.json']).version == 1, 'migrated state is written back at the current version')
    Store.migrations[0] = nil
    T.files['data/state.json'] = '{"version":0,"cs":"OLD-1"}'
    check(Store.load() == 'corrupt', 'a version with no migration is backed up, not guessed at')

    T.files['data/state.json'] = '{"version":1,"nextUnitId":1,"players":{"license:q":{"unitId":7,"callsign":"<bad>","lastChannel":"x y"},"license:r":"junk"},"patches":{}}'
    check(Store.load() == 'loaded', 'file with bad records loads')
    check(Store.state.players['license:q'].callsign == nil and Store.state.players['license:q'].lastChannel == nil, 'invalid saved fields are discarded')
    check(Store.state.players['license:r'] == nil, 'invalid saved records are discarded')
    check(Store.state.nextUnitId == 8, 'next unit id never collides with a saved one')
end

print(('\n%d passed, %d failed'):format(passed, failed))
