$p = require('./promise')
$u = require('./utilities')

retry = (errorHandler, maxRetries, milliseconds, block) ->
  retries = 0
  $p.create (p) ->
    doRetry = ->
      $p.when(block(retries)).then
        success: (results...) -> p.resolve(results...)
        error: (err) ->
          return p.error(err) unless retries < maxRetries
          $p.when(
            if errorHandler.test?
              errorHandler.test(err?.message || "")
            else
              errorHandler(err)
          ).then (retryError) ->
            return p.error(err) unless retryError
            retries++
            $u.pause(Math.pow(2, retries) * milliseconds).then ->
              doRetry()
      null
    doRetry()

module.exports = retry