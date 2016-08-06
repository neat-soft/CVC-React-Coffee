should = require('should')
{throttle, $p, $u, di} = require('../index')
_ = require('lodash')

throw new Error("Hostname is required as first argument") unless process.argv[2]?
console.log "TESTING AGAINST: ", process.argv[2]

ctx = di.context()
ctx.configure {
  redisFactory:
    host: process.argv[2]
}
ctx.registerAll require('../src/redis')
ctx.registerAll require('../src/redis_cache')
ctx.register '$u', $u
ctx.register '$p', $p
ctx.register 'cache', (redisCacheFactory) -> redisCacheFactory('TEST', 100)

ctx.invoke (redisPool, redisPromisePool) ->
  counter = 0
  th = throttle(5)
  doIt = ->
    th ->
      redisPromisePool (redis) ->
        counter++
        console.log "#{counter}, AVAIL: #{redisPool.getAvailable()}, ALLOC:#{redisPool.getAllocated()}" if counter % 100 == 0
        value = 1
        #if counter % 50 == 0
        #  return $p.error(message: "READONLY You can't write against a read only slave.")
        redis.set("TEST_KEY", value).then ->
          redis.get("TEST_KEY").then (result) ->
            $p.resolved()

  failures = 0
  _.map [1..10], ->
    redisPromisePool ->
      $u.pause(1000)
  (_.map [1..2000], ->
    doIt().then
      success: ->
      error: (err) -> console.log "ERRORS: #{failures++}"
      failure: (err) -> console.log "FAILURE: ", err
  ).then ->
    console.log "DONE"
    redisPool.destroyAllIdle()
    console.log "CLEANEDUP"
