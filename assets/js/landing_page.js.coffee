#= require ready
#= require qwery
#= require fastclick
#= require mailcheck
#= require_self

addEvent = (selector, eventType, callback) -> e.addEventListener(eventType,callback,false) for e in qwery(selector)
addClass = (selector, clazz) ->
  for e in qwery(selector)
    className = e.className
    className += " " unless className == ""
    e.className = "#{className}#{clazz}"

removeClass = (selector, clazz) ->
  for e in qwery(selector)
    e.className = e.className.replace(///\b#{clazz}\b///,'');

domready ->
  addEvent '.field input', 'change', (e) ->
    removeClass(@parentNode, 'has-errors')
  addEvent '.email-address input', 'blur', (e) ->
    Mailcheck.run({
      email: @value,
      suggested: (suggestion) =>
        addClass(@parentNode, 'has-suggestion')
        qwery('.suggestion .value', @parentNode)[0].innerHTML = suggestion.full
      empty: =>
        removeClass(@parentNode, 'has-suggestion')
        qwery('.suggestion .value', @parentNode)[0].innerHTML = ""
    });