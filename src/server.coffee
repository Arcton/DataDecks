websocket = require 'ws'
ls = require 'ls'

PORT = 80

server = {}

join_room = (message) ->
    try
        json = JSON.parse message.data
        throw ':(' unless json.id? and server.decks[json.id]?
        deck = server.decks[json.id]
        console.log '%d joining %s', this.datadeck_client, deck.name
        deck.lobby = {
            players: []
        } unless deck.lobby?
        this.lobby = deck.lobby
        this.player = {
            ready: false
            socket: this
        }
        console.log deck.lobby
        deck.lobby.players.unshift this.player
        this.onmessage = player_ready
    catch
        this.terminate()

lobby_ready = (lobby) ->
    console.log lobby
    (return false unless player.ready) for player in lobby.players
    true

player_ready = () ->
    console.log '%d ready', this.datadeck_client
    this.player.ready = true
    if lobby_ready this.lobby
        console.log 'lobby ready'

exports.serve = (arg) ->
    server.decks = (require deck.full for deck in ls __dirname + '/decks/*.json')
    server.decks_summary = { name: deck.name, id: index } for deck,index in server.decks
    deck.max_players = Math.min(6, Math.round(deck.cards.length / 8)) for deck in server.decks

    wss = if Object.prototype.toString.call(arg) is "[object Object]"
        new websocket.Server {server: arg}
    else
        new websocket.Server {port: arg}

    count = 0
    wss.on 'connection', (ws) ->
        ws.datadeck_client = (count += 1)
        console.log '%d Connected', ws.datadeck_client
        ws.send JSON.stringify server.decks_summary
        ws.onmessage = join_room
        ws.on 'close', (event) ->
            console.log '%d Disconnected with: %d', this.datadeck_client, event

# Allows us to be called by another module
# (e.g. we could have the client include us)
unless module.parent?
    standalone = false
    sync = false
    for arg in process.argv.slice 2
        switch arg
            when "--standalone"
                standalone = true
            when "--sync"
                sync = true
            else
                PORT = parseInt arg
    if sync
        (require 'datadeck-data').generate(__dirname + "/decks");
    if standalone
        exports.serve PORT
    else
        client = require 'datadeck-client'
        exports.serve client.serve PORT
