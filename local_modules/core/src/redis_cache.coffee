_ = require('lodash')
moment = require('moment')

exports.RedisCacheFactory = ($p, $u, redisPromisePool) ->
  rootScope = "CACHE"

  stringify = (o) ->
    return o if _.isString(o)
    return o.toString() if _.isNumber(o)
    $u.md5(JSON.stringify(o))

  cacheKey = (scope, key) ->
    "#{rootScope}:#{scope}:#{stringify(key)}"

  evictionKey = (scope) ->
    "#{rootScope}:EVICTION:#{scope}"

  generateEvicitionsKeys = (key) ->
    ss = ""
    _.map key.split(":"), (s) ->
      ss += ":" if ss.length > 0
      ss += s
      evictionKey(ss)

  factory = (scope, timeout) ->
    lookup = (keys...) ->
      redisPromisePool (redis) ->
        eKeyTracker = {}
        orderedEvictionKeys = []
        m = redis.multi().time()
        _.each (keys), (key, index) ->
          fullKey = cacheKey(scope, key)
          m.get(fullKey)
          m.pttl(fullKey)
          _.each generateEvicitionsKeys(fullKey.substring(rootScope.length+1)), (eKey) ->
            eKeyTracker[eKey]?=[]
            eKeyTracker[eKey].push(index)

        _.each eKeyTracker, (keyIndexes, eKey) ->
          orderedEvictionKeys.push(eKey)
          m.get(eKey)

        m.exec().then (results) ->
          time = results.shift()
          time = parseInt(time[0])+parseInt(time[1])/1e6
          values = []
          pttl = []
          for i in [0...keys.length]
            values[i] = results.shift()
            pttl[i] = results.shift()/1000
          for i in [0...orderedEvictionKeys.length]
            eviction = results.shift()
            if eviction?
              eviction = parseFloat(eviction)
              eKey = orderedEvictionKeys[i]
              _.each eKeyTracker[eKey], (keyIndex) ->
                if eviction >= (time - (timeout-pttl[keyIndex]))
                  values[keyIndex] = undefined
          values = _.map(values, (v) -> JSON.parse(v) if v?)
          $p.resolved(values...)

    cache = (key, value) ->
      redisPromisePool (redis) ->
        redis.multi()
          .setex(cacheKey(scope, key), timeout, JSON.stringify(value))
          .exec().then ->
            value

    self = {
      lookup: (keys...) ->
        return lookup(keys...)

      cache: (key, value) ->
        cache(key, value)

      cacheAll: (keyValueMap) ->
        redisPromisePool (redis) ->
          m = redis.multi()
          _.each keyValueMap, (v, k) ->
            m.setex(cacheKey(scope, k), timeout, JSON.stringify(v))
          m.exec().then ->
            keyValueMap

      increment: (key) ->
        redisPromisePool (redis) ->
          redis.incr(cacheKey(scope, key))

      decrement: (key) ->
        redisPromisePool (redis) ->
          redis.decr(cacheKey(scope, key))

      lookupOrCache: (key, block) ->
        lookup(key).then (cachedValue) ->
          return $p.resolved(cachedValue...) if cachedValue?
          $p.when(block()).then (result...) ->
            cache(key, result).then ->
              $p.resolved(result...)

      # NOTE: Eviction evicts all elements added during this millisecond
      evict: (subScope) ->
        es = scope
        es += ":#{subScope}" if subScope
        redisPromisePool (redis) ->
          redis.time().then (time) ->
            time = parseInt(time[0])+parseInt(time[1])/1e6
            redis.setex(evictionKey(es), timeout, time).then ->

      nest: (subScope) ->
        factory("#{scope}:#{subScope}", timeout)

    }
  factory