exports.newrelic = ($options) ->
  if $options?.disabled is true or !$options?
    return {getBrowserTimingHeader: -> ""}
  process.env.NEW_RELIC_APP_NAME = $options?.appName
  process.env.NEW_RELIC_LICENSE_KEY= $options?.licenseKey
  require('newrelic')
