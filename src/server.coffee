websocket = require 'ws'

PORT = 80

exports.serve = (arg) ->
    wss = if Object.prototype.toString.call(arg) is "[object Object]"
        new websocket.Server {server: arg}
    else
        new websocket.Server {port: arg}

    wss.on 'connection', (ws) ->
        console.log 'connected'
        ws.on 'message', (message) ->
            console.log 'Received: %s', message
            ws.send 'echo: ' + message
        ws.on 'close', (event) ->
            console.log 'disconnected with: %d', event

        ws.send 'hi'

# Allows us to be called by another module
# (e.g. we could have the client include us)
unless module.parent?
    standalone = false
    for arg in process.argv.slice 2
        switch arg
            when "--standalone"
                standalone = true
            else
                PORT = parseInt arg
    if standalone
        exports.serve PORT
    else
        client = require 'datadeck-client'
        exports.serve client.serve PORT
