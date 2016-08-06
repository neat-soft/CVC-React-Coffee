_ = require('lodash')
pool = require('./pool')
redis = null

exports.RedisFactory = ($options) -> ->
  redis = require('redis') unless redis?
  redisClient = redis.createClient($options?.port || 6379, $options?.host || "localhost")
  redisClient.select($options.database) if $options?.database?
  redisClient

exports.RedisPool = ($p, redisFactory, $options) ->
  opts = _.defaults($options||{}, {max: 10})
  pool.create
    max: opts.max
    min: opts.min
    create: -> $p.resolved(redisFactory())
    destroy: (redisClient) -> redisClient.end()
    errorHandler: (poolInstance, instance, err) ->
      if err?.message == "READONLY You can't write against a read only slave."
        poolInstance.destroyAll()
      poolInstance.release(instance)

exports.RedisPromisePool = ($p, redisPool) ->
  self = (block) ->
    redisPool (redis) ->
      sendCommand = redis.send_command
      multiCommand = redis.multi
      redis.send_command = (command, args, callback) ->
        if !callback? and args.length>0 and _.isFunction(args[args.length-1])
          callback = args.pop()
        return sendCommand.apply(redis, [command, args, callback]) if callback?
        $p.create (p) ->
          callback = (err, results) ->
            return p.error(err) if err?
            p.resolve(results)
          sendCommand.apply(redis, [command, args, callback])

      redis.eval = (args...) ->
        $p.wrap(redis.__proto__.eval.call(redis, args..., $p.ecb()))

      redis.multi = ->
        multi = multiCommand.apply(redis, [])
        execCommand = multi.exec
        multi.exec = (callback) ->
          return execCommand.apply(multi, [callback]) if callback?
          $p.create (p) ->
            callback = (err, results) ->
              return p.error(err) if err?
              p.resolve(results)
            execCommand.apply(multi, [callback])
        multi
      release = ->
        redis.send_command = sendCommand
        redis.multi = multiCommand

      block(redis).then
        success: (args...) -> release();$p.resolved(args...)
        error: (args...) -> release();$p.error(args...)
        failure: (args...) -> release();$p.failure(args...)

  self.destroyAcquired = -> redisPool.destroyAcquired()
  self.destroyAllIdle = -> redisPool.destroyAllIdle()
  self