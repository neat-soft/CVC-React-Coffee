_ = require('lodash')

_messages = null
module.exports = (key, parameters) ->
  throw new Error("Locale has not been initialized yet") unless _messages?
  message=_messages
  _.map key.split('.'), (part) ->
    message = message?[part]
  console.error "Locale: Key [#{key}] not found" if console?.error? and !message?
  return message
module.exports.setMessages = (messages) ->
  _messages = messages
