{EventEmitter} = require('events')
_ = require('lodash')

class History extends EventEmitter
  currentId = 0
  states = []
  _history = undefined
  backSupported = false
  backOffset = 0
  mount: (window) ->
    return unless window.history?
    backSupported = !((navigator.userAgent.match(/iPhone/i)) || (navigator.userAgent.match(/iPod/i)))
    _history = window.history
    window.addEventListener 'popstate', (e) =>
      if e.state?
        currentId = e.state - backOffset
        entry = states[currentId]
        return unless entry?
        @emit 'popState', _.cloneDeep(entry.state), entry.title, entry.url
        return

  replaceState: (state, title, url) ->
    states[currentId] = {state: _.cloneDeep(state), title: title, url: url}
    _history.replaceState(currentId, title, url) if _history?
    return

  pushState: (state, title, url) ->
    currentId++
    backOffset = 0
    states[currentId] = {state: _.cloneDeep(state), title: title, url: url}
    _history.pushState(currentId, title, url) if _history?
    return

  back: ->
    if _history? and backSupported
      _history.back()
    else
      currentId--
      if backOffset == 0 then backOffset+=2 else backOffset++
      entry = states[currentId]
      @emit 'popState', _.cloneDeep(entry.state), entry.title, entry.url
      return

module.exports = new History()