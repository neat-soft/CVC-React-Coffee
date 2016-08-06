promise = require('./promise')
module.exports = (req) ->
  req.bufferResponse= ->
    req.on 'response', (response) ->
      response._buffers = []
      response.on 'data', (data) ->
        response._buffers.push(data)
      response.on 'end', ->
        response._buffer = Buffer.concat(response._buffers)
    req

  req.restrictResponseSize= (maxResponseSize) ->
    size = 0
    req.on 'response', (response) ->
      response.on 'data', (data) ->
        size+=data.length
        if size > maxResponseSize
          req.abort()
          req.emit 'error', new Error("Response size exceeded #{maxResponseSize}")
    req

  req.defer= ->
    promise.create (p) ->
      req._promise = p
      req.on('error', (err) -> p.error(err))
      req.on 'response', (response) ->
        response.on 'end', ->
          return p.error("Invalid Response #{response.statusCode} FROM #{response.request?.uri?.path}.", response.statusCode, response._buffer.toString()) unless response.statusCode in [200, 201, 204]
          return p.resolve(response) unless response._buffer?
          p.resolve(response._buffer, response.headers, response)
  req
