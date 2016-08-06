should = require('should')
{$p, $u, di} = require('../index')

di.describe 'RedisCacheProvider', (ctx, it) ->
  beforeEach (done) ->
    ctx.registerAll require('../src/redis')
    ctx.registerAll require('../src/redis_cache')
    ctx.register '$u', $u
    ctx.register 'cache', (redisCacheFactory) -> redisCacheFactory('TEST', 100)

    ctx.redisPromisePool (redis) ->
      redis.keys("CACHE:*").then (keys) ->
        return done() unless keys.length > 0
        redis.del(keys...).then -> done()


  afterEach (done) ->
    ctx.redisPool.destroyAcquired().then -> done()

  it "should cache a value", ->
    ctx.cache.cache("KEY", 1).should.eql(1).then ->
      ctx.cache.lookup("KEY").should.eql(1)

  it "should cache result of a block", ->
    ctx.cache.lookupOrCache("KEY", -> 1).should.eql(1).then ->
      ctx.cache.lookupOrCache("KEY", -> 0).should.eql(1)

  it "should return undefined if key is not present", ->
    ctx.cache.lookup("KEY").should.not.exist()

  it "should create a nested scope and cache values", ->
    ctx.cache.lookupOrCache("KEY", -> 1).should.eql(1).then ->
      ctx.cache.nest("TEST2").lookupOrCache("KEY", -> 0).should.eql(0)

  it "should evict an entire scope", ->
    ctx.cache.nest("TEST2").lookupOrCache("KEY", -> 1).should.eql(1).then ->
      ctx.cache.nest("TEST2").lookupOrCache("KEY", -> 0).should.eql(1).then ->
        ctx.cache.evict("TEST2").then ->
          $u.pause(2).then ->
            ctx.cache.nest("TEST2").lookupOrCache("KEY", -> 2).should.eql(2).then ->
              ctx.cache.nest("TEST2").lookupOrCache("KEY", -> 3).should.eql(2)

  it "should evict child scopes", ->
    ctx.cache.nest("TEST2").nest("TEST3:TEST4").lookupOrCache("KEY", -> 1).should.eql(1).then ->
        ctx.cache.evict("TEST2").then ->
          $u.pause(1).then ->
            ctx.cache.nest("TEST2").nest("TEST3:TEST4").lookupOrCache("KEY", -> 2).should.eql(2)

  it "should maintain eviction on elements inside the scope that were added before the eviction", ->
    [ ctx.cache.lookupOrCache("KEY1", -> 1)
      ctx.cache.lookupOrCache("KEY2", -> 2)
    ].then ->
      ctx.cache.evict().then ->
        $u.pause(1).then ->
          ctx.cache.lookupOrCache("KEY1", -> 3).should.eql(3).then ->
            ctx.cache.lookupOrCache("KEY2", -> 4).should.eql(4)

  it "should support caching and looking up a key that is an array", ->
    ctx.cache.lookupOrCache([1,2], -> 3).then ->
      ctx.cache.lookupOrCache([1,2], -> 4).should.equal(3)

  it "should lookup multiple keys", ->
    [ ctx.cache.cache("KEY1", 1)
      ctx.cache.cache("KEY2", 2)
    ].then ->
      ctx.cache.lookup("KEY1", "KEY2", "KEY3").should.eql([1,2,undefined])

  it "should lookup multiple keys across scopes", ->
    [ ctx.cache.nest("TEST1").cache("KEY1", 1)
      ctx.cache.nest("TEST2").cache("KEY2", 2)
    ].then ->
      ctx.cache.lookup("TEST1:KEY1", "TEST2:KEY2", "KEY3").should.eql([1,2,undefined])

  it "should evict correctly when looking up by multiple keys", ->
    [ ctx.cache.nest("TEST1").cache("KEY1", 1)
      ctx.cache.nest("TEST2").cache("KEY2", 2)
    ].then ->
      ctx.cache.evict("TEST1").then ->
        $u.pause(2).then ->
          ctx.cache.lookup("TEST1:KEY1", "TEST2:KEY2", "KEY3").should.eql([undefined,2,undefined])

  it "should support caching a map of key values", ->
    ctx.cache.cacheAll({KEY1: 1, KEY2: 2}).then ->
      ctx.cache.lookup("KEY1", "KEY2", "KEY3").should.eql([1,2,undefined])

  it "should increment a cached value if its an integer", ->
    ctx.cache.cache('KEY', 1).then ->
      ctx.cache.lookup('KEY').should.eql(1).then ->
        ctx.cache.increment('KEY').then ->
          ctx.cache.lookup('KEY').should.eql(2).then ->

  it "should decrement a cached value if its an integer", ->
    ctx.cache.cache('KEY', 2).then ->
      ctx.cache.lookup('KEY').should.eql(2).then ->
        ctx.cache.decrement('KEY').then ->
          ctx.cache.lookup('KEY').should.eql(1).then ->


