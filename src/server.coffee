websocket = require 'ws'
ls = require 'ls'

PORT = 80
MAX_PLAYERS = 6
CARDS_PER_PLAYER = 8
HAND_SIZE = 3

server = {}

join_room = (message) ->
    try
        json = JSON.parse message.data
        throw ':(' unless json.id? and server.decks[json.id]?
        deck = server.decks[json.id]
        console.log '%d joining %s', this.datadeck_client, deck.name
        deck.lobby = {
            deck: deck
            players: []
            cards: index for card,index in deck.cards
            hand_size: 0
        } unless deck.lobby?
        this.lobby = deck.lobby
        this.player = {
            id: this.lobby.players.length
            ready: false
            ws: this
            cards: []
            score: 0
        }
        deck.lobby.players.unshift this.player
        this.onmessage = player_ready
        this.on 'close', (event) ->
            # clean up
            delete this.player.ws
            if this.lobby is this.lobby.deck.lobby
                if lobby_empty this.lobby
                    delete this.lobby.deck.lobby
                else
                    index = this.lobby.players.indexOf this.player
                    if index isnt -1
                        this.lobby.players.splice index, 1
    catch
        this.terminate()

lobby_empty = (lobby) ->
    (return false if player.ws?) for player in lobby.players
    true

lobby_ready = (lobby) ->
    (return false unless player.ready) for player in lobby.players
    true

player_ready = () ->
    console.log '%d ready', this.datadeck_client
    this.player.ready = true
    this.onmessage = null
    if lobby_ready this.lobby
        console.log 'lobby ready'
        this.lobby.deck.lobby = null
        deal_cards this.lobby
        notify_picker this.lobby

lobby_broadcast = (lobby, message, newstate) ->
    if newstate?
        for player in lobby.players
            if player.ws?
                player.ws.send message
                player.ws.onmessage = newstate
    else
        ((player.ws.send message) if player.ws?) for player in lobby.players
    undefined

lobby_picked = (lobby) ->
    (return false unless player.pick?) for player in lobby.players
    true

get_pick_value = (lobby, player) ->
    lobby.deck.cards[player.pick].categories[lobby.category]

increment_score = (lobby, player) ->
    player.score += 1
    lobby_broadcast lobby, JSON.stringify { type: "score", player: player.id, score: player.score }

update_score = (lobby) ->
    best = get_pick_value lobby, lobby.players[0]
    for player in lobby.players
        score = get_pick_value lobby, player
        if lobby.high_good
            best = score if score > best
        else
            best = score if score < best
    ((increment_score lobby, player) if (get_pick_value lobby, player) is best) for player in lobby.players

class tantrum
player_pick_card = (message) ->
    this.onmessage = null
    try
        json = JSON.parse message.data
        throw new tantrum unless json.id? and (index = this.player.cards.indexOf json.id) isnt -1
        this.player.cards.splice index, 1
        this.player.pick = json.id
        if lobby_picked this.lobby
            update_score this.lobby
            for player in this.lobby.players
                console.log this.lobby.deck.cards[player.pick]
                delete player.pick
        deal_cards this.lobby
        notify_picker this.lobby
    catch
        this.terminate()

notify_picker = (lobby) ->
    lobby.picker ?= Math.floor(Math.random() * lobby.players.length)
    lobby.picker = 0 if lobby.picker >= lobby.players.length
    player = lobby.players[lobby.picker]
    if player.ws?
        player.ws.send JSON.stringify { type: "pick_category" }
        player.ws.onmessage = player_pick_category
    else
        notify_picker lobby

player_pick_category = (message) ->
    try
        json = JSON.parse message.data
        throw '(╯°□°）╯︵ ┻━┻' unless json.id? and json.high_good?
        this.lobby.category = json.id
        this.lobby.high_good = json.high_good
        lobby_broadcast this.lobby, JSON.stringify({ type: "category", value: json.id, high_good: json.high_good }), player_pick_card
    catch
        this.terminate()

pick_random_card = (cards) ->
    index = Math.floor(Math.random() * cards.length)
    card = cards[index]
    cards.splice index, 1
    card

deal_cards = (lobby) ->
    while lobby.hand_size < HAND_SIZE
        if lobby.cards.length < lobby.players.length
            console.log "Server out of cards -> no more dealing"
            if lobby.players[0].cards.length < 1
                console.log "Players out of cards -> end of game"
            break
        for player in lobby.players
            card = pick_random_card lobby.cards
            player.cards.push card
            if player.ws?
                player.ws.send JSON.stringify {type: "card", card: lobby.deck.cards[card].name, id: card}
        lobby.hand_size += 1
    undefined

exports.serve = (arg) ->
    server.decks = (require deck.full for deck in ls __dirname + '/decks/*.json')
    server.decks_summary = for deck,index in server.decks
        deck.max_players = Math.min(MAX_PLAYERS, Math.round(deck.cards.length / CARDS_PER_PLAYER))
        { name: deck.name, id: index , categories: deck.categories }

    wss = if Object.prototype.toString.call(arg) is "[object Object]"
        new websocket.Server {server: arg}
    else
        new websocket.Server {port: arg}

    count = 0
    wss.on 'connection', (ws) ->
        ws.datadeck_client = (count += 1)
        console.log '%d Connected', ws.datadeck_client
        ws.send JSON.stringify { type: "decks", data: server.decks_summary }
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
