websocket = require 'ws'
ls = require 'ls'

PORT = 80
MAX_PLAYERS = 6
CARDS_PER_PLAYER = 8
HAND_SIZE = 3

server = {}

class Player
    @count: 0
    constructor: (@ws) ->
        this.id = (Player.count += 1)
        this.ready = false
        this.cards = []
        this.score = 0
    send: (message) ->
        if typeof message is 'object'
            message = JSON.stringify message
        try
            this.ws.send message
        catch err
            console.log '%d error: %s', this.id, err
            this.ws.terminate()
    destroy: ->
        delete this.ws

class Lobby
    constructor: (@deck) ->
        this.players = []
        this.cards = (index for card,index in this.deck.cards)
        this.hand_size = 0
    is_empty: ->
        this.players.length is 0
    is_ready: ->
        (return false unless player.ready) for player in this.players
        true
    all_picked: ->
        (return false unless player.pick?) for player in this.players
        true
    start: ->
        console.log 'Starting %s with %d players', this.deck.name, this.players.length
        this.deck.lobby = null
        this.picker = Math.floor(Math.random() * this.players.length)
        this.deal()
    pick_card: ->
        index = Math.floor(Math.random() * this.cards.length)
        card = this.cards[index]
        this.cards.splice index, 1
        card
    gameover: (reason) ->
        reason ?= "score"
        winners = []
        best_score = 0
        for player in this.players
            if player.score is best_score
                winners.unshift player.id
            else if player.score > best_score
                best_score = player.score
                winners = [ player.id ]
        message = JSON.stringify {
            type: "winner"
            reason: reason
            players: winners
        }
        for player in this.players
            player.ws.onclose = null
            player.ws.onmessage = null
            console.log 'Player %d Disconnected (gameover)', player.id
            try
                ((sock) -> sock.send message, null, (() -> sock.close()))(player.ws)
            catch
    deal: ->
        while this.hand_size < HAND_SIZE
            if this.cards.length < this.players.length
                console.log "Server out of cards -> no more dealing"
                if this.players[0].cards.length < 1
                    console.log "Players out of cards -> end of game"
                    this.gameover()
                    return
                break
            for player in this.players
                card = this.pick_card()
                player.cards.push card
                player.send {
                    type: "card"
                    card: this.deck.cards[card].name
                    description: this.deck.cards[card].description
                    id: card
                }
            this.hand_size += 1
        this.notify_picker()
    notify_picker: ->
        this.picker += 1
        this.picker %= this.players.length if this.picker >= this.players.length
        player = this.players[this.picker]
        player.send {
            type: "pick_category"
        }
        player.ws.onmessage = player_pick_category
    send: (message, newstate) ->
        if typeof message is 'object'
            message = JSON.stringify message
        if newstate?
            for player in this.players
                player.send message
                player.ws.onmessage = newstate
        else
            player.send message for player in this.players
        undefined
    update_score: ->
        # find best card
        best = this.deck.cards[this.players[0].pick].categories[this.category]
        for player in this.players
            score = this.deck.cards[player.pick].categories[this.category]
            if this.high_good
                best = score if score > best
            else
                best = score if score < best
        # update the score for all players who picked the best card
        for player in this.players
            if this.deck.cards[player.pick].categories[this.category] is best
                player.score += 1
                this.send {
                    type: "score"
                    player: player.id
                    score: player.score
                }
    reveal_cards: ->
        this.send { type: "reveal", cards: for player in this.players
            card = this.deck.cards[player.pick]
            {
                name: card.name
                description: card.description
                id: player.pick
                value: card.categories[this.category]
            }
        }
    round_end: ->
        this.reveal_cards()
        this.update_score()
        delete player.pick for player in this.players
        this.hand_size -= 1
        this.deal()

onclose = (event) ->
    console.log 'Player %d Disconnected with: %d', this.player.id, event.code
    # clean up
    this.player.destroy
    if this.lobby is this.lobby.deck.lobby and this.lobby.is_empty()
        delete this.lobby.deck.lobby
    else
        index = this.lobby.players.indexOf this.player
        (this.lobby.players.splice index, 1) if index isnt -1
        (this.lobby.gameover "default") if this.lobby.players.length is 1

join_room = (message) ->
    try
        json = JSON.parse message.data
        throw null unless json.id? and server.decks[json.id]?
        deck = server.decks[json.id]
        deck.lobby = new Lobby deck unless deck.lobby?
        this.lobby = deck.lobby
        this.player = new Player this
        deck.lobby.players.unshift this.player
        this.onmessage = player_ready
        this.onclose = onclose
        console.log 'Player %d joining %s', this.player.id, deck.name
        this.player.send {
            type: "player"
            id: this.player.id
        }
        this.lobby.start() if this.lobby.players.length >= this.lobby.deck.max_players
    catch err
        console.log err
        this.terminate()

player_ready = () ->
    console.log 'Player %d is ready for %s', this.player.id, this.lobby.deck.name
    this.player.ready = true
    this.onmessage = null
    this.lobby.start() if this.lobby.players.length > 1 and this.lobby.is_ready()

player_pick_card = (message) ->
    this.onmessage = null
    try
        json = JSON.parse message.data
        throw null unless json.id? and (index = this.player.cards.indexOf json.id) isnt -1
        this.player.cards.splice index, 1
        this.player.pick = json.id
        this.lobby.round_end() if this.lobby.all_picked()
    catch err
        console.log err
        this.terminate()

player_pick_category = (message) ->
    try
        json = JSON.parse message.data
        throw null unless json.id? and json.high_good?
        this.lobby.category = json.id
        this.lobby.high_good = json.high_good
        this.lobby.send {
            type: "category"
            value: json.id
            high_good: json.high_good
        }, player_pick_card
    catch err
        console.log err
        this.terminate()

exports.serve = (arg) ->
    server.decks = (require deck.full for deck in ls __dirname + '/decks/*.json')
    server.decks_summary = for deck,index in server.decks
        deck.max_players = Math.min(MAX_PLAYERS, Math.round(deck.cards.length / CARDS_PER_PLAYER))
        { name: deck.name, id: index , categories: deck.categories }

    wss = if Object.prototype.toString.call(arg) is "[object Object]"
        new websocket.Server {server: arg}
    else
        new websocket.Server {port: arg}

    wss.on 'connection', (ws) ->
        ws.send JSON.stringify {
            type: "decks"
            data: server.decks_summary
        }
        ws.onmessage = join_room

# Allows us to be called by another module
# (e.g. we could have the client include us)
unless module.parent?
    sync = true
    for arg in process.argv.slice 2
        switch arg
            when "--nosync"
                sync = false
            else
                PORT = parseInt arg
    (require 'datadeck-data').generate(__dirname + "/decks") if sync
    exports.serve PORT
