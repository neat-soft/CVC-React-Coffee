$p = require('./promise')
$u = require('./utilities')
_ = require("lodash")
retry = require("./retry")

exports.RestClientFactory = ($logger) ->
  request = require('request')

  ($options) ->
    baseUrl = $options.baseUrl
    urlSuffix = $options.urlSuffix || ""
    auth = _.merge {sendImmediately: true}, $options.auth if $options.auth?
    _send = send = (opts) ->
      opts = _.merge {auth: auth}, opts
      $p.wrap(request(opts, $p.ecb())).then
        success: (response, body) ->
          if (response.headers['content-type']||"").match(/json/)?
            try
              body = JSON.parse(body) if body?
            catch e
              $logger.error "Failed to parse response for [#{opts.url}]", body
          else if body.length == 0
            body = null
          if !_.isString(body) and response.statusCode==400
            #we have a JSON validation error, let's not wrap it in an error
            return $p.error(body)
          if response.statusCode>=400
            errSeparator = "\n========================================================\n"
            errBody = body
            errBody = $u.inspect(errBody, 10) if _.isObject(errBody)
            err = new Error("Error [#{response.statusCode}] from [#{(opts.method || "get").toUpperCase()} #{opts.url}]#{errSeparator}#{errBody}#{errSeparator}")
            err.statusCode = response.statusCode
            err.requestUrl = opts.url
            err.body = body
            err.responseHeaders = response.headers
            return $p.error(err)
          body

    if $options?.retry? and $options.retry > 0
      retryHandler = (err) -> err.statusCode >= 500
      send = (opts) ->
        if opts.noRetry is true
          delete opts.noRetry
          return _send(opts)
        retry(retryHandler, $options.retry, $options.retryDelay || 1000, -> _send(opts))

    return self = {
      constructPath: (path, pathArgs..., data, opts) ->
        for i in [1..2]
          if !_.isObject(data) and data?
            pathArgs.push(data)
            [data, opts] = [opts, undefined]
        pathArgs = _.filter(pathArgs, (arg) -> arg?)
        pathArgs = _.map(pathArgs, encodeURIComponent).join("/")
        pathArgs = "/"+ pathArgs if pathArgs.length > 0
        [path+pathArgs, data, opts]

      post: (path, pathArgs..., body, opts) ->
        [path, body, opts] = self.constructPath(path, pathArgs..., body, opts)
        contentType = opts?.contentType
        if Buffer.isBuffer(body)
          contentType ?= 'application/octet-stream'
        else if body?
          body = JSON.stringify(body)
          contentType ?= 'application/json'
        opts = _.merge {
          method: 'post'
          url: "#{baseUrl}#{path}#{urlSuffix}"
          headers: 'content-type': contentType
          body: body
        }, opts
        delete opts.contentType
        send(opts)

      put: (path, pathArgs..., body, opts) ->
        [path, body, opts] = self.constructPath(path, pathArgs..., body, opts)
        self.post(path, body, _.merge({method:'PUT'}, opts))

      delete: (path, pathArgs..., body, opts) ->
        [path, body, opts] = self.constructPath(path, pathArgs..., body, opts)
        self.post(path, body, _.merge({method:'DELETE'}, opts))

      get: (path, pathArgs..., queryString, opts) ->
        [path, queryString, opts] = self.constructPath(path, pathArgs..., queryString, opts)
        opts = _.merge {
          url: "#{baseUrl}#{path}#{urlSuffix}"
          qs: queryString
        }, opts
        send(opts)
    }

