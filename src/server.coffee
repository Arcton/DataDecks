connect = require 'connect'
serve_static = require 'serve-static'
websocket = require 'ws'

serve = serve_static __dirname + '/../static'
connect().use(serve).listen 8080
