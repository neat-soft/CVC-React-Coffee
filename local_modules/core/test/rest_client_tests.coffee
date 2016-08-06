should = require('should')
{$p, $u, di} = require('../index')
http = require('http')
url = require('url')

di.describe 'RestClient', (ctx, it) ->
  handlers = []
  server = undefined
  beforeEach (done) ->
    ctx.registerAll require('../src/rest_client')
    ctx.register 'restClient', (restClientFactory) -> restClientFactory(retry: 2, retryDelay: 50, baseUrl: "http://localhost:9999")
    handlers = []
    server = http.createServer((args...) -> handlers.shift()(args...))
    server.listen(9999, -> done())

  afterEach (done) ->
    server.close(-> done())

  it "should properly construct a path when path arguments are provider", ->
    ctx.restClient.constructPath("/start", "arg1", "2", "?injectme", {a:1}, {method:'PUT'}).should.eql ["/start/arg1/2/%3Finjectme", {a:1}, {method:'PUT'}]
    ctx.restClient.constructPath("/start", "arg1", "2", "?injectme", {a:1}).should.eql ["/start/arg1/2/%3Finjectme", {a:1}, undefined]
    ctx.restClient.constructPath("/start", "arg1", "2", "?injectme").should.eql ["/start/arg1/2/%3Finjectme", undefined, undefined]
    ctx.restClient.constructPath("/start", "arg1", "2", "?injectme", undefined).should.eql ["/start/arg1/2/%3Finjectme", undefined, undefined]
    ctx.restClient.constructPath("/start", {a:1}).should.eql ["/start", {a:1}, undefined]
    ctx.restClient.constructPath("/start", undefined, {method:'PUT'}).should.eql ["/start", undefined, {method: 'PUT'}]

  it "should send get requests to a server", ->
    handlers.push (req, res) ->
      req.method.should.equal("GET")
      req.url.should.equal("/hello?alpha=1")
      url.parse(req.url, true).query.alpha.should.equal('1')
      res.end("world!")
    ctx.restClient.get('/hello', {alpha: 1}).should.equal("world!")

  it "should send post requests to a server", ->
    handlers.push (req, res) ->
      req.method.should.equal("POST")
      req.url.should.equal("/hello")
      res.end("world!")

  it "should send put requests to a server", ->
    handlers.push (req, res) ->
      req.method.should.equal("PUT")
      req.url.should.equal("/hello")
      res.end("world!")

    ctx.restClient.put('/hello').should.equal("world!")

  it "should convert json responses into objects", ->
    handlers.push (req, res) ->
      res.setHeader('content-type', 'application/json')
      res.end(JSON.stringify({a: 1}))
    ctx.restClient.post('/hello').should.eql({a:1})

  it "should retry requests", ->
    handlers.push (req, res) ->
      res.writeHead(500)
      res.end("ERROR")
    handlers.push (req, res) ->
      res.writeHead(500)
      res.end("ERROR")
    handlers.push (req, res) ->
      res.writeHead(500)
      res.end("ERROR")
    ctx.restClient.get('/hello', {alpha: 1}).then
      success: -> should.fail("should fail")
      error: -> handlers.should.eql([])

  it "should not retry 404 requests", ->
    handlers.push (req, res) ->
      res.writeHead(404)
      res.end("ERROR")
    ctx.restClient.get('/hello', {alpha: 1}).then
      success: -> should.fail("should fail")
      error: (status, err) ->
        handlers.should.eql([])

  it "should not wrap 400 json errors as Error", ->
    handlers.push (req, res) ->
      res.setHeader('content-type', 'application/json')
      res.writeHead(400)
      res.end(JSON.stringify(error: "Hello World"))
    ctx.restClient.get('/hello', {alpha: 1}).should.eql(error: [error: "Hello World"])

  it "should return proper result after a failed retry", ->
    handlers.push (req, res) ->
      res.writeHead(500)
      res.end("ERROR")
    handlers.push (req, res) ->
      res.end("world!")
    ctx.restClient.get('/hello', {alpha: 1}).should.equal("world!")

  it "should support disabling retry mechanism", ->
    handlers.push (req, res) ->
      res.writeHead(500)
      res.end("ERROR")
    ctx.restClient.get('/hello', {alpha: 1}, noRetry: true).then
      success: -> should.fail("should fail")
      error: -> handlers.should.eql([])

  it "should not treat 2xx codes as errors", ->
    handlers.push (req, res) ->
      res.writeHead(202)
      res.end("OK")
    ctx.restClient.get('/hello', {alpha: 1}, noRetry: true).then ->
      handlers.should.eql([])

  it "should properly handle Buffers", ->
    handlers.push (req, res) ->
      req.method.should.equal("PUT")
      req.headers['content-type'].should.equal('application/octet-stream')
      buffers = []
      req.on 'data', (chunk) -> buffers.push(chunk)
      req.on 'end', ->
        res.end("Hello #{Buffer.concat(buffers).toString()}")
    ctx.restClient.put('/hello', new Buffer("World")).should.equal("Hello World")
