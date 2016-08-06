_ = require('lodash')
React = require('react')
d = _.merge React.DOM, require('./common'), require('./canvas')
{createFactory} = d
{EventEmitter} = require('events')
stores = require('./stores')
{Profile, PhotoPlaceholder} = require('./profile')
Support = require('./support')
$l = require('./locale')
History = require('./history')

Header = createFactory
  propTypes:
    onChangePath: React.PropTypes.func.isRequired

  componentDidMount: -> @props.notificationStore.on 'change', @handleChange
  componentWillUnmount: -> @props.notificationStore.removeListener 'change', @handleChange
  handleChange: -> @forceUpdate()
  handleClick: (path, e) ->
    e.preventDefault()
    @refs.menu.hide()
    @props.onChangePath(path)
  handleSignout: (e) ->
    e.preventDefault()
    @refs.menu.hide()
    if confirm($l('signOutConfirmation'))
      @props.signOut()
  handleHelp: (e) ->
    e.preventDefault() if e?
    @refs.menu.hide()
    @refs.support.show()
  handleShowMenu: (e) ->
    e.preventDefault()
    @refs.menu.show()
  render: ->
    profile = @props.myProfileSummary
    newMessages = @props.notificationStore.getNewMessages()
    newDiscover = @props.notificationStore.getNewDiscover()
    newVisitors = @props.notificationStore.getNewVisitors()
    newLikedBy = @props.notificationStore.getNewLikedBy()
    showUpgrade = @props.features.billing?.available and !@props.features.messaging?.available
    d.div {className: "navigation-container#{if showUpgrade then ' show-upgrade' else ''}"},
      Support {ref: 'support', restClient: @props.rootRestClient}
      d.SlidingMenu {ref: 'menu'},
        d.div {className: 'logo-white'}
        if showUpgrade
          d.Button {className: 'subscribe', onClick: @handleClick.bind(null, '/upgrade')},
            d.Glyph(glyph: 'certificate')
            d.span {}, $l('tooltips.subscribe')
        d.Button {onClick: @handleClick.bind(null, '/browse')},
          d.Glyph(glyph: 'search')
          d.span {}, $l('tooltips.browse')
        d.Button {onClick: @handleClick.bind(null, '/discover')},
          d.Glyph(glyph: 'users')
          d.span {}, $l('tooltips.discover')
          (d.span {className: 'counter'}, newDiscover) if newDiscover > 0
    if @props.features.liked_by?.enabled
      d.Button {onClick: @handleClick.bind(null, '/liked_by')},
        d.Glyph(glyph: 'star')
        d.span {}, $l('tooltips.likedBy')
        (d.span {className: 'counter'}, newLikedBy) if newLikedBy > 0
    d.Button {onClick: @handleClick.bind(null, '/inbox')},
      d.Glyph(glyph: 'envelope')
      d.span {}, $l('tooltips.inbox')
      (d.span {className: 'counter'}, newMessages) if newMessages > 0
    if @props.features.visitors?.enabled
      d.Button {onClick: @handleClick.bind(null, '/visitors')},
        d.Glyph(glyph: 'eye')
        d.span {}, $l('tooltips.visitors')
        (d.span {className: 'counter'}, newVisitors) if newVisitors > 0
    d.Button {onClick: @handleClick.bind(null, '/myprofile')},
      d.Glyph(glyph: {M: 'male', 'F': 'female'}[profile.gender])
      d.span {}, $l('tooltips.myprofile')
    d.Button {onClick: @handleClick.bind(null, '/photos')},
      d.Glyph(glyph: 'camera')
      d.span {}, $l('tooltips.photos')
    d.Button {onClick: @handleClick.bind(null, '/settings')},
      d.Glyph(glyph: 'wrench')
      d.span {}, $l('tooltips.settings')
    d.Button {onClick: @handleHelp},
      d.Glyph(glyph: 'question')
      d.span {}, $l('tooltips.help')
    d.Button {onClick: @handleSignout},
      d.Glyph(glyph: 'sign-out')
      d.span {}, $l('tooltips.signout')
    d.div {className: 'header'}, d.div {className: 'outer'}, d.div {className: 'inner'},
      if @props.showBackButton
        d.a {className: 'sliding-menu-link', href: "#", onClick: @props.onBack},
          d.Glyph(glyph: 'arrow-left')
      else
        d.a {className: 'sliding-menu-link', href: "#", onClick: @handleShowMenu},
          d.Glyph(glyph: 'bars')
      d.div {className: 'logo-container'},
        d.div {className: 'clickable long-logo-white', onClick: => @handleClick.bind(null, '/browse')}
        d.div {className: 'clickable site-name', onClick: => @handleClick.bind(null, '/browse')}
      d.a {className: 'primary button-link', title: $l('tooltips.subscribe'), href: "#", onClick: @handleClick.bind(null, '/upgrade')}, $l("tooltips.subscribe") if showUpgrade
    d.a {className: 'secondary circle-link', title: $l('tooltips.browse'), href: "#", onClick: @handleClick.bind(null, '/browse')}, d.Glyph(glyph: 'search')
    d.div {className: 'secondary discover'},
      d.a {className: 'circle-link', title: $l('tooltips.discover'), href: "#", onClick: @handleClick.bind(null, '/discover')}, d.Glyph(glyph: 'users')
      (d.span {className: 'counter'}, if newDiscover < 100 then newDiscover else "99+") if newDiscover > 0
    d.div {className: 'secondary inbox'},
      d.a {className: 'circle-link', title: $l('tooltips.inbox'), href: "#", onClick: @handleClick.bind(null, '/inbox')}, d.Glyph(glyph: 'envelope')
      (d.span {className: 'counter'}, newMessages) if newMessages > 0
    d.a {className: 'other circle-link', title: $l('tooltips.myprofile'), href: "#", onClick: @handleClick.bind(null, '/myprofile')},
      d.Glyph(glyph: {M: 'male', 'F': 'female'}[profile.gender])
    d.a {className: 'other circle-link', title: $l('tooltips.settings'), href: "#", onClick: @handleClick.bind(null, '/settings')}, d.Glyph(glyph: 'wrench')
    d.a {className: 'other circle-link', title: $l('tooltips.signout'), href: "#", onClick: @handleSignout}, d.Glyph(glyph: 'sign-out')

Home = createFactory
  getIntlMessage: (key) -> key
  render: ->
    d.div {className: 'home'}, [
      d.h1 {}, "Welcome [#{@props.accountGuid}] to #{@getIntlMessage('common.siteTitle')}! Looking at #{@props.path}"
    ]...

routes =
  '^\/$': {component: Home}
  '^\/upload_photo$': {component: require('./photos'), props: {continueTo: '/'}, showBackButton: true}
  '^\/photos$': {component: require('./photos'), dataPath: 'photos', showBackButton: true}
  '^\/browse$': {component: require('./browse'), dataPath: 'browse', store: stores.BrowseStore}
  '^\/profile\/.*$': {component: Profile, dataPath: 'profile', showBackButton: true}
  '^\/myprofile$': {component: Profile, dataPath: 'profile', props: {editable: true}}
  '^\/inbox$': {component: require('./messaging').Inbox, dataPath: 'inbox'}
  '^\/conversation\/.*$': {component: require('./messaging').Conversation, dataPath: 'conversation', showBackButton: true}
  '^\/discover$': {component: require('./discover').Discover, dataPath: 'discover'}
  '^\/liked_by$': {component: require('./profile_list').LikedBy, dataPath: 'likedBy'}
  '^\/visitors$': {component: require('./profile_list').Visitors, dataPath: 'likedBy'}
  '^\/upgrade$': {component: require('./upgrade').Upgrade, dataPath: 'upgrade', showBackButton: true}
  '^\/upgrade\/.*$': {component: require('./upgrade').PaymentMethod, dataPath: 'upgrade', showBackButton: true}
  '^\/settings$': {component: require('./settings').Settings}
  '^\/settings/change_password$': {component: require('./settings').ChangePassword, showBackButton: true}
  '^\/settings/email_preferences$': {component: require('./settings').EmailPreferences, dataPath: 'emailPreferences', showBackButton: true}
  '^\/settings/remove_profile$': {component: require('./settings').RemoveProfile, dataPath: 'removeProfile', showBackButton: true}
  '^\/settings/manage_subscription$': {component: require('./settings').ManageSubscription, dataPath: 'subscription', showBackButton: true}

parseRoute = (path) ->
  parsed = path.match(/([^?]*)($|\?(.*)$)/)
  params = parsed?[3]
  if params?
    params = _.object _.map params.split("&"), (kv) ->
      pairs = kv.split("=")
      pairs[1] = decodeURIComponent(pairs[1]) if pairs[1]?
      pairs
  {route: parsed?[1], qs: parsed?[2], params: params}

findRoute = (path) ->
  route = parseRoute(path).route
  for own r, def of routes
    return def if route.match(RegExp(r))?

module.exports = createFactory
  getDefaultProps: -> {
  notificationStore: new stores.NotificationStore()
  }
  getInitialState: -> _.omit(@props, 'messages', 'notificationStore')
  componentWillMount: ->
    $l.setMessages(@props.messages)
    @props.notificationStore.init(@props.counters)
    d.setCookies(@props.cookies)

  componentDidMount: ->
    @pushStateEnabled = history?.pushState?
    React.initializeTouchEvents(true)
    @historyCounter=0
    @errorCounter=0
    window.onerror = (errorMessage, url, lineNumber, columnNumber, errObject) =>
      return if @errorCounter++ > 5
      info = {
        message: errorMessage
        stackTrace: errObject?.stack
      }
      @ajax("/javascript_error", "POST", info)
    window.gaReady = =>
      @trackPageview(window.location.pathname || window.location.toString())
    if @pushStateEnabled
      History.mount(window)
      History.on 'popState', (state, title, url) =>
        @historyCounter--
        state = _.merge state, {backNavigation: true}
        @setState(state)

  ajax: (url, type, data, callbacks) ->
    if _.isFunction(callbacks)
      callbacks =
        success: callbacks
        error: (xhr, status, err) =>
          @setState {successMessage: undefined, errorMessage: xhr.responseText || "Unable to process request, please try again later!"}
    headers = {'local-cookies': JSON.stringify(@props.cookies)}
    if type == 'GET'
      if url.indexOf("?")>=0 then url+="&#{Math.random()}" else url+="?#{Math.random()}"
    $.ajax
      url: url
      type: type
      accepts: 'application/json'
      dataType: 'json'
      data: data
      headers: headers
      success: (args...) =>
        if args[2]?.getAllResponseHeaders?
          newUrl = args[2]?.getResponseHeader('change-location')
          if newUrl?.length>0
            window.location = newUrl
            return
        if args[0]?._redirectTo?
          @handleChangePath(args[0]?._redirectTo)
        else
          callbacks.success(args...) if callbacks?.success?
      error: (res, args...) ->
        err = res.responseJSON
        err = err?.errors || err
        err = null if err? and _.isArray(err) and err.length == 0
        callbacks.error(res, args..., err) if callbacks?.error?

  trackPageview: (pageUrl) ->
    pageUrl?=""
    pageUrl=pageUrl.replace(/\?.*/,'')
    pageUrl=pageUrl.replace(/\/profile\/.*/,'/profile')
    pageUrl=pageUrl.replace(/\/conversation\/.*/,'/conversation')
    if window.ga?
      window.ga('set', 'page', pageUrl)
      window.ga('send', 'pageview')

  handleChangePath: (newPath, force) ->
    route = findRoute(newPath)
    newUrl = "/app#{newPath}"
    return window.location = newUrl unless @pushStateEnabled
    History.replaceState @state, "", window.location
    @ajax newUrl, "GET", null, (newState) =>
      if @props.version != newState.version
        return window.location = newUrl
      newState.backNavigation = false
      newState.path = newPath
      @props.notificationStore.updateCounters(newState.counters)
      newState.errorMessage = null
      History.pushState newState, "", newUrl
      @historyCounter++
      @trackPageview(newUrl)
      @forceUpdate = true
      @setState(newState)

  handleBack: ->
    History.back()

  shouldComponentUpdate: (nextProps, nextState) ->
    @state.path!=nextState.path || @forceUpdate

  render: ->
    @forceUpdate = false
    route = parseRoute(@state.path)
    primaryComponent = findRoute(route.route)
    defaultCallbacks = (newState) =>
      newState = _.omit newState, 'path'
      @setState(newState)
    dataPath = primaryComponent.dataPath
    restClientFactory = (path, _defaultCallbacks) => {
    get: (url, data, callbacks) => @ajax("/app#{path}#{url}", "GET", data, callbacks || _defaultCallbacks)
    post: (url, data, callbacks) => @ajax("/app#{path}#{url}", "POST", data, callbacks || _defaultCallbacks)
    put: (url, data, callbacks) => @ajax("/app#{path}#{url}", "PUT", data, callbacks || _defaultCallbacks)
    delete: (url, data, callbacks) => @ajax("/app#{path}#{url}", "DELETE", data, callbacks || _defaultCallbacks)
    }
    restClient = restClientFactory(route.route, defaultCallbacks)
    rootRestClient = restClientFactory("")
    console.log @historyCounter
    sharedProps = {
      backNavigation: @state.backNavigation || false
      accountGuid: @props.accountGuid
      onChangePath: @handleChangePath
      path: @state.path
      route: route
      restClient: restClient
      rootRestClient: rootRestClient
      myProfileSummary: @props.myProfileSummary
      notificationStore: @props.notificationStore
      features: @state.features || @props.features
      showBackButton: @historyCounter>0 and primaryComponent.showBackButton
      onBack: @handleBack
      onUpdateFeatures: (features) => @setState(features: features)
      onCustomerSupport: => @refs.header.handleHelp()
      signOut: =>
        $("""<form id='sign-out' method='post' action='/signout' style='display:none'></form>""").appendTo('body')
        $('#sign-out').submit()
    }
    dataProps = _.cloneDeep @state[primaryComponent.dataPath] || {}
    componentProps = _.merge {ref: 'primaryComponent'}, sharedProps, restClient, primaryComponent.props || {}, dataProps || {}
    d.div {className: 'app-body curvesconnect'},
      d.div {className: 'background'},
        d.div {className: 'outer'},
          d.div {className: 'inner'},

            d.div {className: 'outer'}, d.div {className: 'inner'},
              (d.div {style: color: 'red'}, @state.errorMessage) if @state.errorMessage?
    (d.div {style: color: 'green'}, @state.errorMessage) if @state.successMessage?
    Header(_.merge {ref: 'header', myProfileSummary: @props.myProfileSummary}, sharedProps)
    primaryComponent.component(componentProps)