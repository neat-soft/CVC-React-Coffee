generic_pool = require('generic-pool')
$p = require('./promise')
$u = require('./utilities')
_ = require('lodash')

exports.create = (config) ->
  acquired = 0
  acquiredInstances = []
  expireInstances = []
  expireInstancesPromise = null
  config = _.defaults config, {
    max: 10
  }

  poolOptions =
    name   : config.name,
    max    : config.max,
    min    : config.min,
    create : (callback) -> $p.when(config.create()).then callback
    destroy: (instance) -> config.destroy(instance) if config.destroy?
    validate: (instance) -> instance._destroy!=true
  localPool = generic_pool.Pool(poolOptions)

  wrappedPool = (callback) ->
    doAcquire = (block) ->
      return wrappedPool.with(block) if block?
      acquired++
      instancePromise = $p.create (p) ->
        localPool.acquire $u.trace("pool #{localPool.getName()}", (err, instance) ->
          acquiredInstances.push(instance);
          return p.error(err) if err?
          p.resolve(instance)
        )
    if callback? and config.acquire?
      result = config.acquire(doAcquire, callback)
      return result if result?
    doAcquire(callback)

  wrappedPool.with = (callback) ->
    wrappedPool().then (instance) ->
      $p.when(callback(instance)).then
        success: (results...) ->
          wrappedPool.release(instance)
          $p.resolved(results...)
        error: (results...) ->
          if config.errorHandler?
            config.errorHandler(wrappedPool, instance, results...)
          else
            wrappedPool.release(instance)
          $p.error(results...)

  wrappedPool.release = (instance, destroy) ->
    acquired-- if instance in acquiredInstances
    acquiredInstances = _.without(acquiredInstances, instance)
    if instance in expireInstances or destroy is true
      instance._destroy = true
      expireInstances = _.without(expireInstances, instance)
      if expireInstancesPromise? and expireInstances.length == 0
        setImmediate ->
          localPool.destroyAllNow()
          expireInstancesPromise.resolve()
          expireInstancesPromise = null
    localPool.release(instance)

  wrappedPool.destroy = (instance) ->
    wrappedPool.release(instance, true)
  wrappedPool.getAvailable = -> config.max - acquired
  wrappedPool.getIdle = -> localPool.availableObjectsCount()
  wrappedPool.getWaiting = -> localPool.waitingClientsCount()
  wrappedPool.getSize = -> config.max
  wrappedPool.getAllocated = -> localPool.getPoolSize()
  wrappedPool.getName = -> localPool.getName()
  wrappedPool.destroyAllIdle= ->
    localPool.destroyAllNow()
  wrappedPool.destroyAll = ->
    localPool.destroyAllNow()
    expireInstances = _.unique(expireInstances.concat(acquiredInstances))
    return $p.resolved if expireInstances.length == 0
    return expireInstancesPromise.then(->) if expireInstancesPromise?
    expireInstancesPromise = $p.create()
    expireInstancesPromise.then ->
  wrappedPool.destroyAcquired = ->
    (_.map acquiredInstances, (instance) ->
      config.destroy(instance) if config.destroy?
    ).then ->

  wrappedPool.getStats = -> {
    size: @getSize()
    available: @getAvailable()
    idle: @getIdle()
    allocated: @getAllocated()
    acquired: acquired
    waiting: @getWaiting()
  }

  wrappedPool

