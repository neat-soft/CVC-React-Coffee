_ = require('lodash')
moment = require('moment')

exports.RedisQueueProvider = ($p, $u, redisPromisePool, queueMonitorFactory, time, $logger) ->
  maxRetries = 5
  ref = (queue, message) ->
    message = message.toString() if _.isNumber(message)
    str = JSON.stringify([queue, message])
    $u.md5(str)

  killRefs = (redis, queue, refs) ->
    return if refs.length == 0
    deadQueue = "#{queue}:dead"
    redis.watch("queue:#{queue}:transaction_counter", "queue:#{deadQueue}:transaction_counter").then ->
      redis.hmget("queue:#{queue}:messages", refs...).then (messages) ->
        throw new Error("Missing messages for refs") if messages.length < refs.length
        args = []
        newDelays = []
        for i in [0..refs.length]
          if messages[i]?
            newRef = ref(deadQueue, messages[i])
            newDelays.push 0
            newDelays.push newRef
            args.push newRef
            args.push messages[i]
        return redis.unwatch() if args.length == 0
        multi = redis.multi()
          .incr("queue:#{queue}:transaction_counter")
          .incr("queue:#{deadQueue}:transaction_counter")
          .zrem("queue:#{queue}:retries", refs...)
          .zrem("queue:#{queue}:delay", refs...)
          .hdel("queue:#{queue}:messages", refs...)
        multi.zadd("queue:#{queue}:dead:delay", newDelays...) if newDelays.length > 0
        multi.hmset("queue:#{queue}:dead:messages", args...) if args.length > 0
        multi.exec().then (results...) ->
          return killRefs(redis, queue, refs) unless results[0]?
          refs.length

  getRedisTime = (redis) ->
    redis.time().then (redisTime) ->
      parseInt(redisTime[0])+parseInt(redisTime[1])/1e6

  requeueExpired = (redis, queue, elements) ->
    redis.watch("queue:#{queue}:transaction_counter").then ->
      getRedisTime(redis).then (redisTime) ->
        [ redis.zrangebyscore("queue:#{queue}:delay", "-inf", redisTime, "LIMIT", 0, elements - 1)
          redis.zrangebyscore("queue:#{queue}:retries", maxRetries, "+inf")
        ].then (requeueRefs, failedRefs) ->
          maxElementsRequeued = requeueRefs.length == elements
          return redis.unwatch() if requeueRefs.length is 0
          failedRefs = _.filter failedRefs, (ref) -> ref in requeueRefs
          requeueRefs = _.reject requeueRefs, (ref) -> ref in failedRefs
          if requeueRefs.length == 0
            redis.unwatch()
            return killRefs(redis, queue, failedRefs)
          m = redis.multi()
            .incr("queue:#{queue}:transaction_counter")
            .rpush("queue:#{queue}:pending", requeueRefs...)
            .zrem("queue:#{queue}:delay", requeueRefs...)
          _.each requeueRefs, (ref) ->
            m.zincrby("queue:#{queue}:retries", 1, ref)
          m.exec().then (results...) ->
            if results[0]!=null
              killRefs(redis, queue, failedRefs)
              $logger.debug "[#{queue}] requeued #{requeueRefs.length}", $u.concatString(requeueRefs,',')
            #self.requeueExpired() if maxElementsRequeued

  return self =
    computeReference: (queue, message) ->
      ref(queue, message)

    enqueue: (queue, message, priority, processAfter) ->
      reference = ref(queue, message)
      $logger.debug "[#{queue}] [#{reference}] enqueue #{message}"
      self.isEnqueued(queue, reference).then (isEnqueued) ->
        return reference if isEnqueued
        redisPromisePool (redis) ->
          redis.multi()
            .lpush("queue:#{queue}:pending", reference)
            .zrem("queue:#{queue}:delay", reference)
            .zrem("queue:#{queue}:retries", reference)
            .hset("queue:#{queue}:messages", reference, JSON.stringify(message))
            .exec().then -> reference

    dequeue: (queue, retryIn, waitFor) ->
      return $p.failure("TIMEOUT OUT OF 0 IS NOT SUPPORTED FOR DEQUEUE OPERATION [#{queue}]") if waitFor is 0
      redisPromisePool (redis) ->
        popCommand = if waitFor?
          -> redis.brpoplpush "queue:#{queue}:pending", "queue:#{queue}:processing", 1
        else
          -> redis.rpoplpush "queue:#{queue}:pending", "queue:#{queue}:processing"
        timeout = time.unixTime() + waitFor*1000

        getNextReference = ->
          getRedisTime(redis).then (redisTime) ->
            redis.zrangebyscore("queue:#{queue}:delay", "-inf", redisTime, "LIMIT", 0, 1).then (expiredReference) ->
              $p.when(requeueExpired(redis, queue, 100) if expiredReference.length > 0).then ->
                popCommand().then (reference) ->
                  return getNextReference() if !reference? and waitFor? and time.unixTime() < timeout
                  $logger.debug "[#{queue}] POPPED #{reference}" if reference?
                  reference

        tryNextReference = ->
          #$logger.debug "[#{queue}] [tryNextReference] #{moment(timeout)}"
          getNextReference().then (reference) ->
            return $p.resolved(null, null) unless reference?
            getRedisTime(redis).then (redisTime) ->
              delayUntil = redisTime + retryIn
              redis.multi()
                .hget("queue:#{queue}:messages", reference)
                .zscore("queue:#{queue}:retries", reference)
                .zadd("queue:#{queue}:delay", delayUntil, reference)
                .lrem("queue:#{queue}:processing", 0, reference)
                .lrem("queue:#{queue}:pending", 0, reference)
                .exec().then (results) ->
                  retries = parseInt(results[1]||'0')
                  if !results[0]?
                    return redis.zrem("queue:#{queue}:delay", reference).then ->
                      tryNextReference()
                  return tryNextReference() if retries > maxRetries
                  $p.resolved(reference, JSON.parse(results[0]))

        tryNextReference()

    isEnqueued: (queue, reference) ->
      redisPromisePool (redis) ->
        redis.hexists("queue:#{queue}:messages", reference).then (result) ->
          result == 1

    getDelay: (queue, reference) ->
      redisPromisePool (redis) ->
        [ redis.hexists("queue:#{queue}:messages", reference)
          redis.zscore("queue:#{queue}:delay", reference)
          getRedisTime(redis)
        ].then (exists, delayedUntil, redisTime) ->
          return null unless exists is 1
          return 0 unless delayedUntil?
          Math.max(0, parseFloat(delayedUntil) - redisTime)

    setDelay: (queue, reference, delay) ->
      redisPromisePool (redis) ->
        [ redis.hexists("queue:#{queue}:messages", reference)
          getRedisTime(redis)
        ].then (exists, redisTime) ->
          return unless exists is 1
          redis.zadd "queue:#{queue}:delay", redisTime + delay, reference

    listAllMessages: (queue, limit) ->
      limit ||= 100
      redisPromisePool (redis) ->
        redis.lrange("queue:#{queue}:pending", -limit, -1).then (refs) ->
          return [] if refs.length == 0
          refs.reverse()
          redis.hmget("queue:#{queue}:messages", refs...).then (messages) ->
            _.map(messages, JSON.parse)

    getRetryCount: (queue, reference) ->
      redisPromisePool (redis) ->
        redis.zscore("queue:#{queue}:retries", reference).then (count) ->
          parseInt(count || '0')

    getSize: (queue) ->
      redisPromisePool (redis) ->
        redis.hlen "queue:#{queue}:messages"

    getQueueStats: (queue) ->
      redisPromisePool (redis) ->
        stats = {
          size        : redis.hlen("queue:#{queue}:messages")
          pending     : redis.llen("queue:#{queue}:pending")
          processing  : redis.llen("queue:#{queue}:processing")
          delayed     : redis.zcard("queue:#{queue}:delay")
          retrying    : redis.zcard("queue:#{queue}:retries")
        }
        stats.toPromise()

    getQueueSizes: () ->
      redisPromisePool (redis) ->
        redis.keys("queue:*:messages").then (queues) ->
          queueNames = _.chain(queues).map((q) -> q.replace(/queue:(.*):.*/,'$1'))
                                      .uniq()
                                      .value()
          m = redis.multi()
          _.each queueNames, (q) -> m.hlen "queue:#{q}:messages"
          m.exec().then (results) ->
            sizes = {}
            _.each queueNames, (q, i) ->
              sizes[q]=results[i]
            sizes

    remove: (queue, refs...) ->
      redisPromisePool (redis) ->
        multi = redis.multi()
        _.each refs, (reference) ->
          multi.lrem("queue:#{queue}:pending", 0, reference)
        multi
          .zrem("queue:#{queue}:delay", refs...)
          .zrem("queue:#{queue}:retries", refs...)
          .hdel("queue:#{queue}:messages", refs...)
          .exec()

    removeQueue: (queue) ->
      (redisPromisePool (redis) ->
        redis.keys("queue:#{queue}:*").then (keys) ->
          return unless keys.length > 0
          redis.del(keys...)
      ).then ->

    monitor: (queue, retryDelay, blockingTimeout, block) ->
      queueMonitorFactory(self).monitor(queue, retryDelay, blockingTimeout, block)

exports.QueueMonitorFactory = ($p) -> (redisQueueProvider) ->
  stop = false
  return self = {
    stop: -> stop = true
    monitor: (queue, retryDelay, blockingTimeout, block) ->
      forwardQueue = (queue, retryDelay, blockingTimeout, block) ->
        return if stop is true
        redisQueueProvider.dequeue(queue, retryDelay, blockingTimeout).then (ref, message) ->
          return forwardQueue(queue, retryDelay, blockingTimeout, block) unless ref?
          result = block(message)
          ($p.when(result).then
            success: ->
            error: (e) -> redisQueueProvider.enqueue("#{queue}:dead", message)
          ).then
            success: ->
              redisQueueProvider.remove(queue, ref).then ->
                forwardQueue(queue, retryDelay, blockingTimeout, block)
            failure: (e) ->
              forwardQueue(queue, retryDelay, blockingTimeout, block)
        null
      forwardQueue(queue, retryDelay, blockingTimeout, block)
  }

if require.main is module
  cluster = require('cluster')
  di = require('./di')

  createContext = ->
    ctx = di.context()
    ctx.registerAll require('./redis')
    ctx.register '$u', require('./utilities')
    ctx.register '$p', require('./promise')
    ctx.register '$logger', {
      #debug: console.log
      debug: ->
    }
    ctx.register 'time', {
      currentTime: -> new Date(self.unixTime()-skew)
      unixTime: -> (new Date()).getTime()
    }
    ctx.registerAll exports
    ctx

  runMaster = ->
    console.log "RUNNING CONCURRENCY TEST"
    consumerCount = 20
    maxSize = 2000
    maxCounter = 2000
    consumers = {}

    process.execPath = 'coffee' unless __filename.match(/.*js$/)?
    for consumer in [0...consumerCount]
      console.log "STARTING", consumer
      cluster.fork()
    cluster.on 'online', (consumer) ->
      console.log "#{consumer.id} ONLINE"
      consumers[consumer.id]=consumer

    cluster.on 'exit', (consumer, code, signal) ->
      delete consumers[consumer.id]
      console.log "RESTARTING"
      cluster.fork()

    ctx = createContext()
    ctx.invoke ($p, redisQueueProvider, redisPromisePool) ->
      redisQueueProvider.removeQueue("TEST").then ->
        console.log "TEST QUEUE DELETED STARTING TEST WITH #{consumerCount} CONSUMERS"
        counter = 0
        showQueue = ->
          [ redisQueueProvider.getQueueStats("TEST")
            redisQueueProvider.getQueueStats("TEST:dead")
          ].then (stats, deadStats) ->
            console.log stats, deadStats
            redisPromisePool (redis) ->
              redis.zrangebyscore("queue:TEST:COUNTERS", 2, '+inf').then (retried) ->
                console.log "RETRIED: #{retried.length}"
                setTimeout showQueue, 2000
        fillQueue = ->
          redisQueueProvider.getSize("TEST").then (size) ->
            toAdd = maxSize - size
            (for i in [0...toAdd]
              redisQueueProvider.enqueue("TEST", counter++)
            ).then ->
              if counter < maxCounter
                setTimeout fillQueue, 100
        fillQueue()
        showQueue()

  runConsumer = ->
    ctx = createContext()
    ctx.invoke ($p, redisQueueProvider, redisPromisePool) ->
      redisPromisePool (redis) ->
        redisQueueProvider.monitor "TEST", 2, 1, (msg) ->
          #console.log "ABOUT TO FAIL #{msg}" if msg % 20 == 0
          throw new Error("MSG SHOULD NOT BE NULL") unless msg?
          redis.zincrby("queue:TEST:COUNTERS", 1, msg).then ->
            return $p.failure("FAIL #{msg}") if msg % 2 == 0
        $p.create()

  if cluster.isMaster
    runMaster()
  else
    runConsumer()