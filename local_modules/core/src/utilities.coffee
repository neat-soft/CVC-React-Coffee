_ = require('lodash')
crypto = require('crypto')
promise = require('./promise')
scope = require('./scope')
http = require('http')
https = require('https')
domain = require('domain')
{spawn} = require('child_process')
util = require('util')

exports.randomInt = (from,to) -> Math.round(Math.random() * (to-from) + from)

exports.randomString = (length) ->
  alpha = 'abcdefghjklmnpqrstuvwxyz0123456789'
  guid = ""
  guid += alpha[Math.round(Math.random()*(alpha.length-1))] for i in [1..length]
  guid

exports.extendObject = (parent, obj) ->
  obj.__proto__ = parent
  obj

exports.curry = (f, args...) ->
  (params...) ->
    f(args..., params...)

exports.pipeToBuffer = (stream) ->
  promise.promise (p) ->
    buffers = []
    size = 0
    if stream.prebuffer?
      for chunk in stream.prebuffer
        buffers.push(chunk)
        size+=chunk.length
      stream.prebuffer=null
    stream.on 'data', (chunk) ->
      buffers.push(chunk)
      size+=chunk.length
    stream.on 'end', ->
      buffer = new Buffer(size)
      pos = 0
      for b in buffers
        b.copy buffer, pos, 0
        pos+=b.length
      p.resolve buffer
    stream.resume()

exports.md5 = (string) ->
  md5 = crypto.createHash('md5')
  md5.update(string)
  md5.digest('hex')

exports.encrypt = (string, key, algorithm) ->
  algorithm ||= 'aes256'
  cipher = crypto.createCipher(algorithm, key);
  cipher.update(string, 'utf8', 'hex') + cipher.final('hex');

exports.decrypt = (string, key, algorithm) ->
  algorithm ||= 'aes256'
  decipher = crypto.createDecipher(algorithm, key);
  decipher.update(string, 'hex', 'utf8') + decipher.final('utf8');

exports.isEqual = (a, b) ->
  return JSON.stringify(Object.keys(a).sort()) == JSON.stringify(Object.keys(b).sort())

exports.argsToString = (args) ->
  JSON.stringify(args).replace(/\"/g,'')

exports.toProperCase = (value) ->
  return value.replace /\w\S*/g, (txt) -> return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase()

exports.toCamelCase = (value) ->
  return value.replace /_\w/g, (txt) -> return txt.charAt(1).toUpperCase() + txt.substr(2).toLowerCase()

exports.toSnakeCase = (value) ->
  return value.replace(/([a-z])([A-Z0-9])/g, (match, lower, upper)-> "#{lower}_#{upper.toLowerCase()}")

exports.toVariableName = (value) ->
    name = value.replace /[A-Z][a-z0-9 ]+|[A-Z][A-Z][a-z0-9 ]+|[A-Z]+$|[A-Z ]+(?=[A-Z][a-z0-9 ]+)/g, (txt) ->
      return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase().replace(/[ ]*/g,'')
    name.charAt(0).toLowerCase() + name.substr(1)

exports.concatString = (value, delim) ->
    return "" if value.length is 0
    return value.reduce (x,y) -> "#{x}#{delim}#{y}"

exports.toMap = (value, keyProp, valueProp) ->
    map = {}
    for item in value
      map[item[keyProp]] = (if valueProp? then item[valueProp] else item)
    map

exports.toJson = (value, prettyPrint) -> JSON.stringify(value, Object.keys(value).sort(), prettyPrint||false)

exports.toJson = (value, prettyPrint) -> JSON.stringify(value, undefined, prettyPrint||false)

exports.toInt = (value) ->
    return NaN if _.isNaN(value)
    return Math.floor(value) if typeof(value) == 'number'
    return parseInt(value.toString())

exports.clean = (value) ->
    for own k,v of value
      delete value[k] unless v?
    value

exports.hashCode = (value) ->
    return Math.abs(value.split("").reduce(((a,b) ->
      a=((a<<5)-a)+b.charCodeAt(0)
      return a&a
    ),0))

exports.objectHmac = (key, o) ->
  hmac = crypto.createHmac('sha256', key)
  parameters = _.sortBy(_.keys(o), (param) -> param)
  _.each parameters, (param) ->
    hmac.write(param, o[param] || "") unless param == "_sig"
  hmac.digest("hex")

exports.parseArguments = (func) ->
  ARGS = /^function\s*[^\(]*\(\s*([^\)]*)\)/m;
  ARG_SPLIT = /,/;
  ARG = /^\s*(_?)(\S+?)\1\s*$/;
  STRIP_COMMENTS = /((\/\/.*$)|(\/\*[\s\S]*?\*\/))/mg;
  throw new Error("Unable to parse arguments for non functions") unless _.isFunction(func)
  argNames = [];
  funcText = func.toString().replace(STRIP_COMMENTS, '');
  argMatches = funcText.match(ARGS);
  _.each argMatches[1].split(ARG_SPLIT), (arg) ->
    arg.replace ARG, (all, underscore, name) ->
      argNames.push(name);

  return argNames;

exports.merge = (objects...) ->
  merged = {}
  _.each objects, (o) ->
    merged = _.defaults(merged, o)
  merged

exports.invokeByName = (that, func, namedParams...) ->
  args = exports.parseArguments(func)
  mergedParams = exports.merge({$argNames: args}, namedParams...)
  params = (mergedParams[arg] for arg in args)
  func.apply(that, params)

exports.pullLast = (args...) ->
  return args unless args.length>0 and args[0]?
  start = -1
  for i in [args.length..0]
    start = Math.max(start, i) if args[i]?
  args[args.length-1] = args[start]
  args[start] = undefined
  args

exports.arrayEquals = (a1, a2) ->
  throw new Error("Only arrays can be compared") unless (_.isArray(a1) or !a1?) and (_.isArray(a2) or !a2?)
  return true if a1 == a2
  return false if a1? and !a2?
  return false if a1.length != a2.length
  for e in a1
    return false unless e in a2
  return true

exports.spawnBuffered = (command, args...) ->
  args = _.flatten(args) if args.length == 1
  proc = spawn command, args
  output = []
  error = []
  streams = promise.create()
  done = promise.create()
  proc.stdout.on 'data', (data) -> output.push data
  proc.stderr.on 'data', (data) -> error.push data
  proc.on 'close', -> streams.resolve(output, error)
  proc.on 'exit', (code, signal) ->
    streams.then (output, error) ->
      [output, error]=[Buffer.concat(output), Buffer.concat(error)]
      return done.error(code, output.toString(), error.toString()) unless code == 0
      done.resolve(output, error)
  proc.then = (args...) ->
    done.then(args...)
  proc

exports.spawnUnbufferedOutput = (command, args...) ->
  args = _.flatten(args) if args.length == 1
  proc = spawn command, args
  error = []
  streams = promise.create()
  done = promise.create()
  proc.stderr.on 'data', (data) -> error.push data
  proc.on 'close', -> streams.resolve(error)
  proc.on 'exit', (code, signal) ->
    streams.then (error) ->
      error=Buffer.concat(error)
      return done.error(code, error.toString()) unless code == 0
      done.resolve(error)
  proc.then = (args...) ->
    done.then(args...)
  proc

exports.downloadRemoteUrl = (url, maxSizeInBytes, timeout) ->
  timeout?=600*1000
  promise.create (p) ->
    pkg = if url.indexOf('https') == 0 then https else http
    request = pkg.get url, (response) ->
      buffers = []
      size = 0
      return p.error("Invalid Response #{response.statusCode}", response.statusCode) unless response.statusCode in [200, 302]
      response.setTimeout(timeout)
      response.connection.setTimeout(timeout)
      response.on 'data', (buffer) ->
        buffers.push buffer
        size+=buffer.length
        if size > maxSizeInBytes
          request.abort()
          p.error("OBJECT_TOO_LARGE")
      response.on 'error', (err) -> p.error(err)
      response.on 'end', -> p.resolve(Buffer.concat(buffers), response.headers)
    request.on 'error', (err) -> p.error(err)
    request.setTimeout(timeout)
    request.end()

exports.pause = (timeInMs) ->
  promise.create (p) ->
    setTimeout p.resolveCallback(), timeInMs

exports.bindToActiveDomain = (f) ->
  forceNoDomain = (args...) ->
    process.domain.exit() while process.domain?
    f.apply(this, args)
  return forceNoDomain unless domain.active?
  domain.active.bind f

exports.batchProcess = (list, batchSize, block) ->
  return block(list) if list.length <= batchSize
  start = 0
  promise.create (p) ->
    processChunk = ->
      chunk = list.slice(start, start + batchSize)
      block(chunk).then ->
        if (start+batchSize)<list.length
          start+=batchSize
          processChunk()
        else
          p.resolve()
      null
    processChunk()

exports.chunkArray = (array, chunkSize) ->
  chunks = []
  start = 0
  while(start<array.length)
    chunks.push array.slice(start, start+chunkSize)
    start = start+chunkSize
  chunks

exports.pageBlock = (startPage, block) ->
  [startPage, block] = [1, startPage] unless block?
  promise.create (p) ->
    page = startPage
    processChunk = ->
      promise.when(block(page)).then
        error: (args...) -> p.error(args...)
        failure: (args...) -> p.failure(args...)
        success: (keepGoing) ->
          if keepGoing?.totalRows? and keepGoing?.pageSize?
            keepGoing = (keepGoing.totalRows/keepGoing.pageSize) >= page
          page++
          return processChunk() if keepGoing
          p.resolve()
      null
    processChunk()

exports.hashCode = (str) ->
  hash = 0;
  return hash if str.length == 0
  str = str.toString()
  for i in [0...str.length]
    char = str.charCodeAt(i)
    hash = ((hash<<5)-hash)+char
    hash = hash & 0xFFFFFFFF
  return Math.abs(hash);

exports.trace = (label, cb) ->
  return cb unless scope.context?.tracer?
  scope.context.tracer(label, cb)

exports.inspect = (object, depth) ->
  util.inspect(object, depth: depth)

exports.groupByPrefix = (obj, prefixes) ->
  grouped = {}
  patterns = {}
  for own k, v of prefixes
    patterns[v] = ///^#{k}([A-Z])///
  for own k, v of obj
    match = null
    matchedProperty = null
    for own property, pattern of patterns
      unless match?
        match = k.match(pattern)
        matchedProperty = property if match?
    if match?
      k = match[1].toLowerCase() + k.substring(match[0].length)
      grouped[matchedProperty]?={}
      grouped[matchedProperty][k]=v
    else
      grouped[k]=v
  grouped

exports.flattenObject = (obj, prefixMapping) ->
  flattened = {}
  for own k, v of obj
    if _.isObject(v) and !_.isFunction(v) and !_.isDate(v)
      k = prefixMapping[k] if prefixMapping?[k]?
      for own k1, v1 of v
        flattened["#{k}#{k1.substring(0,1).toUpperCase()}#{k1.substring(1)}"] = v1
    else
      flattened[k]=v
  flattened

exports.omit = (props...) -> (obj) ->
  promise.when(obj).then (obj) ->
    return _.omit(obj, props) unless _.isArray(obj)
    _.map (obj), (row) -> _.omit(row, props)
